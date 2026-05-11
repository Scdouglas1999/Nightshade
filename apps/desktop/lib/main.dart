import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge;
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_updater/nightshade_updater.dart';
// Why still imported: UpdatePushDiscovery (LAN update-push responder) lives in
// nightshade_webrtc/discovery.dart. The server (NightshadeWebServer) is gone
// in §2.2 but discovery primitives remain.
import 'package:nightshade_webrtc/nightshade_webrtc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path/path.dart' as path;

import 'package:nightshade_app/nightshade_app.dart';
import 'headless_api_server.dart';
import 'main_headless.dart' as headless;

// Current app version - must match version.yaml
const String appVersion = '2.5.0';
const int appBuildNumber = 5;

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Check for headless mode flag
  final isHeadless = args.contains('--headless') ||
      Platform.environment['NIGHTSHADE_HEADLESS'] == '1';

  if (isHeadless) {
    // Delegate to the modern headless entry point (main_headless.dart)
    headless.main(args);
    return;
  }

  // Initialize the native bridge
  final appSupportDir = await getApplicationSupportDirectory();
  final logDir = path.join(appSupportDir.path, 'logs');
  await bridge.NativeBridge.init(logDirectory: logDir);

  // Initialize profile storage
  final appDir = await getApplicationDocumentsDirectory();
  final profileDir = path.join(appDir.path, 'Nightshade', 'profiles');
  await Directory(profileDir).create(recursive: true);
  await bridge.NativeBridge.apiInitProfileStorage(storagePath: profileDir);

  // Initialize settings storage
  await bridge.NativeBridge.apiInitSettingsStorage(storagePath: profileDir);

  // Initialize window manager for desktop (only in GUI mode)
  await windowManager.ensureInitialized();

  // Initialize catalog manager with app data directory
  await _initializeCatalogManager();

  const windowOptions = WindowOptions(
    size: Size(1600, 900),
    minimumSize: Size(1200, 700),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'Nightshade 2.0',
  );

  final container = ProviderContainer(
    overrides: [
      // Initialize backendProvider with FfiBackend immediately for desktop GUI
      backendProvider.overrideWith((ref) {
        final notifier = BackendNotifier(ref);
        notifier.useLocalBackend();
        return notifier;
      }),
    ],
  );

  // Check if we should start minimized
  final shouldStartMinimized = await _shouldStartMinimized(container);

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();

    // Minimize after showing if setting is enabled
    if (shouldStartMinimized) {
      await windowManager.minimize();
    }
  });

  // Start background services for mobile access (non-blocking)
  _startBackgroundServices(container);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const NightshadeApp(isDesktop: true),
    ),
  );
}

/// Start background services for mobile/remote access.
///
/// Why this delegates to [HeadlessApiServer]: pre-§2.2 the desktop GUI used a
/// separate `NightshadeWebServer` (~4700 LoC with its own handler wiring) while
/// headless mode used the modular `HeadlessApiServer`. Mobile/web clients saw
/// different endpoint sets depending on which mode was running. Consolidating
/// onto a single server eliminates that schism and gives the GUI the modular
/// handlers, pairing flow, scoped tokens, and middleware stack for free.
void _startBackgroundServices(ProviderContainer container) {
  // Start in background - don't block UI
  Future.microtask(() async {
    HeadlessApiServer? apiServer;
    StreamSubscription? collaborationSubscription;
    AppSettings? queuedWebServerSettings;
    bool isApplyingWebServerSettings = false;
    // Persist the operator's auth token across restarts so the dashboard does
    // not have to re-pair on every app launch. Mobile clients also rely on
    // this token surviving a server restart.
    final persistentToken = await _getOrCreateRemoteAccessToken();

    Future<void> stopApiServer(
      AppSettings settings, {
      String error = '',
    }) async {
      await collaborationSubscription?.cancel();
      collaborationSubscription = null;

      final running = apiServer;
      apiServer = null;
      if (running != null) {
        await running.stop();
      }

      container.read(webServerStateProvider.notifier).setStopped(
            configuredPort: settings.webServerPort,
            actualPort: settings.webServerPort,
            bindLocalOnly: false,
            requiresAuthentication: true,
            dashboardAvailable: true,
            lastError: error,
          );
    }

    Future<void> applyWebServerSettings(AppSettings settings) async {
      await stopApiServer(settings);

      if (!settings.webServerEnabled) {
        debugPrint('[MAIN] Remote access is disabled in settings');
        return;
      }

      final nextServer = HeadlessApiServer(
        port: settings.webServerPort,
        container: container,
        // GUI mode is always LAN-accessible (the operator opted in via the
        // remote access toggle); pairing/scoped tokens still gate writes.
        bindLocalOnly: false,
        authToken: persistentToken,
        requireAuth: true,
      );

      try {
        debugPrint(
            '[MAIN] Starting authenticated desktop remote access server...');
        await nextServer.start();
        apiServer = nextServer;
        debugPrint(
          '[MAIN] Remote access started on port ${nextServer.actualPort}',
        );

        container.read(webServerStateProvider.notifier).setRunning(
              isRunning: true,
              actualPort: nextServer.actualPort,
              configuredPort: settings.webServerPort,
              bindLocalOnly: false,
              requiresAuthentication: true,
              dashboardAvailable: true,
            );

        collaborationSubscription =
            nextServer.collaborationManager.stream.listen((collabState) {
          container
              .read(webServerStateProvider.notifier)
              .setActiveViewers(collabState.viewers.length);
        });

        try {
          final pushService = container.read(pushNotificationServiceProvider);
          nextServer.setPushNotificationStream(
            pushService.notifications
                .map((notification) => notification.toJson()),
          );
          debugPrint('[MAIN] Push notifications wired to web server');
        } catch (e) {
          debugPrint('[MAIN] Push notification setup failed: $e');
        }
      } catch (e) {
        debugPrint('[MAIN] Remote access failed to start: $e');
        await nextServer.stop();
        await stopApiServer(
          settings,
          error: 'Remote access failed to start: $e',
        );
      }
    }

    Future<void> scheduleWebServerUpdate(AppSettings settings) async {
      queuedWebServerSettings = settings;
      if (isApplyingWebServerSettings) {
        return;
      }

      isApplyingWebServerSettings = true;
      try {
        while (queuedWebServerSettings != null) {
          final nextSettings = queuedWebServerSettings!;
          queuedWebServerSettings = null;
          await applyWebServerSettings(nextSettings);
        }
      } finally {
        isApplyingWebServerSettings = false;
      }
    }

    try {
      AppSettings? lastAppliedSettings;
      container.listen<AsyncValue<AppSettings>>(
        appSettingsProvider,
        (_, next) {
          final settings = next.valueOrNull;
          if (settings == null) {
            return;
          }

          final shouldRestart = lastAppliedSettings == null ||
              lastAppliedSettings!.webServerEnabled !=
                  settings.webServerEnabled ||
              lastAppliedSettings!.webServerPort != settings.webServerPort;

          if (!shouldRestart) {
            return;
          }

          lastAppliedSettings = settings;
          unawaited(scheduleWebServerUpdate(settings));
        },
        fireImmediately: true,
      );

      // Start LAN push update receiver
      try {
        var isReceivingLanPush = false;
        final pushSecret = await _getOrCreatePushSecret();
        final lanPushReceiver = LanPushReceiver(
          currentVersion: appVersion,
          currentBuildNumber: appBuildNumber,
          pushSecret: pushSecret,
        );
        lanPushReceiver.onUpdateReceived = (manifest, stagingPath) {
          isReceivingLanPush = false;
          debugPrint(
              '[MAIN] Update received via LAN push: ${manifest.version}');
          LanPushNotifier.notifyUpdateReceived(manifest, stagingPath);
        };
        lanPushReceiver.onProgress = (received, total, progress, message) {
          isReceivingLanPush = total > 0 && received < total;
          debugPrint(
              '[MAIN] LAN push progress: ${(progress * 100).toStringAsFixed(1)}% - $message');
          LanPushNotifier.notifyProgress(received, total, progress, message);
        };
        lanPushReceiver.onError = (error) {
          isReceivingLanPush = false;
          debugPrint('[MAIN] LAN push error: $error');
          LanPushNotifier.notifyError(error);
        };
        await lanPushReceiver.startServer();
        debugPrint('[MAIN] LAN push receiver started on port 45680');

        // Start responding to update push discovery
        await UpdatePushDiscovery.startResponding(
          name: 'Nightshade',
          version: appVersion,
          buildNumber: appBuildNumber,
          isReceivingCallback: () => isReceivingLanPush,
        );
        debugPrint('[MAIN] Update push discovery responder started');
      } catch (e) {
        debugPrint('[MAIN] LAN push receiver failed: $e');
      }
    } catch (e) {
      debugPrint('[MAIN] Background services failed to initialize: $e');
    }

    debugPrint(
      '[MAIN] Desktop GUI remote access is authenticated for non-local clients.',
    );
  });
}

Future<void> _initializeCatalogManager() async {
  try {
    final appDataDir = await getApplicationSupportDirectory();
    final catalogDir = path.join(appDataDir.path, 'catalogs');
    await CatalogManager.instance.initialize(catalogDir);
  } catch (e) {
    debugPrint('Failed to initialize catalog manager: $e');
  }
}

/// Check if the app should start minimized based on settings
/// This directly reads from the database before Riverpod is initialized
Future<bool> _shouldStartMinimized(ProviderContainer container) async {
  try {
    final dao = container.read(settingsDaoProvider);
    final value = await dao.getSetting('start_minimized');
    return value == 'true';
  } catch (e) {
    debugPrint('Error checking start minimized setting: $e');
    return false;
  }
}

/// Load or generate the persistent bearer token used by the embedded API
/// server in GUI mode. Why persist on disk: rotating the token on every app
/// launch would force every paired mobile/dashboard client to re-pair through
/// the 6-digit pairing flow. The token is stored under the platform
/// application-support directory which is per-user-private on all desktop
/// platforms, so leaking the file out of that scope requires either local
/// account compromise or operator action.
Future<String> _getOrCreateRemoteAccessToken() async {
  final appData = await getApplicationSupportDirectory();
  final tokenFile = File(path.join(appData.path, 'remote_access_token.txt'));

  if (await tokenFile.exists()) {
    final existing = (await tokenFile.readAsString()).trim();
    if (existing.isNotEmpty) {
      return existing;
    }
  }

  // 32 bytes of cryptographically random hex; matches the entropy that
  // HeadlessApiServer.requireAuth uses internally when no token is supplied.
  final rng = Random.secure();
  final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
  final token = bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  await tokenFile.parent.create(recursive: true);
  await tokenFile.writeAsString(token);
  debugPrint(
    '[MAIN] Generated new remote-access bearer token at ${tokenFile.path}. '
    'Pair via the dashboard or copy the token from this file to configure '
    'mobile/CLI clients.',
  );
  return token;
}

/// Load or generate the LAN push authentication secret.
/// The secret is persisted in the app data directory so it survives restarts.
/// The same secret must be configured on the push tool (dev machine) to authenticate.
Future<String> _getOrCreatePushSecret() async {
  final appData = await getApplicationSupportDirectory();
  final secretFile = File(path.join(appData.path, 'push_secret.txt'));

  if (await secretFile.exists()) {
    final secret = (await secretFile.readAsString()).trim();
    if (secret.isNotEmpty) {
      return secret;
    }
  }

  // Generate a new secret and persist it
  final secret = LanPushReceiver.generatePushSecret();
  await secretFile.parent.create(recursive: true);
  await secretFile.writeAsString(secret);
  debugPrint('[MAIN] Generated new LAN push secret. '
      'Configure this on the push tool: ${secretFile.path}');
  return secret;
}
