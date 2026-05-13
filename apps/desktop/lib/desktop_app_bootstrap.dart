import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_updater/nightshade_updater.dart';
// Why still imported: UpdatePushDiscovery (LAN update-push responder) lives in
// nightshade_webrtc/discovery.dart. The server (NightshadeWebServer) is gone
// in §2.2 but discovery primitives remain.
import 'package:nightshade_webrtc/nightshade_webrtc.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'headless_api_server.dart';

const String _logSource = 'DesktopBootstrap';

/// Start background services for mobile/remote access.
///
/// Why this delegates to [HeadlessApiServer]: pre-§2.2 the desktop GUI used a
/// separate `NightshadeWebServer` (~4700 LoC with its own handler wiring) while
/// headless mode used the modular `HeadlessApiServer`. Mobile/web clients saw
/// different endpoint sets depending on which mode was running. Consolidating
/// onto a single server eliminates that schism and gives the GUI the modular
/// handlers, pairing flow, scoped tokens, and middleware stack for free.
void startBackgroundServices(
  ProviderContainer container, {
  required String appVersion,
  required int appBuildNumber,
}) {
  Future.microtask(() => _runBackgroundServices(
        container,
        appVersion: appVersion,
        appBuildNumber: appBuildNumber,
      ));
}

Future<void> _runBackgroundServices(
  ProviderContainer container, {
  required String appVersion,
  required int appBuildNumber,
}) async {
  final logger = container.read(loggingServiceProvider);
  final persistentToken = await _getOrCreateRemoteAccessToken(logger);

  final apiLifecycle = _ApiServerLifecycle(
    container: container,
    logger: logger,
    persistentToken: persistentToken,
  );

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
        unawaited(apiLifecycle.scheduleUpdate(settings));
      },
      fireImmediately: true,
    );

    await _startLanPushReceiver(
      logger: logger,
      appVersion: appVersion,
      appBuildNumber: appBuildNumber,
    );
  } catch (e) {
    logger.error(
      'Background services failed to initialise',
      source: _logSource,
      fields: {'error': '$e'},
    );
  }

  logger.info(
    'Desktop GUI remote access is authenticated for non-local clients',
    source: _logSource,
  );
}

/// Owns the lifecycle of the embedded [HeadlessApiServer] for the desktop GUI.
/// Restarts in response to settings changes are queued so a rapid sequence of
/// edits cannot leave two server instances racing on the same port.
class _ApiServerLifecycle {
  final ProviderContainer container;
  final LoggingService logger;
  final String persistentToken;

  HeadlessApiServer? _apiServer;
  StreamSubscription<dynamic>? _collaborationSubscription;
  AppSettings? _queuedSettings;
  bool _isApplying = false;

  _ApiServerLifecycle({
    required this.container,
    required this.logger,
    required this.persistentToken,
  });

  Future<void> scheduleUpdate(AppSettings settings) async {
    _queuedSettings = settings;
    if (_isApplying) {
      return;
    }

    _isApplying = true;
    try {
      while (_queuedSettings != null) {
        final next = _queuedSettings!;
        _queuedSettings = null;
        await _apply(next);
      }
    } finally {
      _isApplying = false;
    }
  }

  Future<void> _stop(AppSettings settings, {String error = ''}) async {
    await _collaborationSubscription?.cancel();
    _collaborationSubscription = null;

    final running = _apiServer;
    _apiServer = null;
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

  Future<void> _apply(AppSettings settings) async {
    await _stop(settings);

    if (!settings.webServerEnabled) {
      logger.info('Remote access is disabled in settings', source: _logSource);
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
      logger.info('Starting authenticated desktop remote access server',
          source: _logSource);
      await nextServer.start();
      _apiServer = nextServer;
      logger.info(
        'Remote access started',
        source: _logSource,
        fields: {'port': nextServer.actualPort},
      );

      container.read(webServerStateProvider.notifier).setRunning(
            isRunning: true,
            actualPort: nextServer.actualPort,
            configuredPort: settings.webServerPort,
            bindLocalOnly: false,
            requiresAuthentication: true,
            dashboardAvailable: true,
          );

      _collaborationSubscription =
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
        logger.info('Push notifications wired to web server',
            source: _logSource);
      } catch (e) {
        logger.warning(
          'Push notification setup failed',
          source: _logSource,
          fields: {'error': '$e'},
        );
      }
    } catch (e) {
      logger.error(
        'Remote access failed to start',
        source: _logSource,
        fields: {'error': '$e'},
      );
      await nextServer.stop();
      await _stop(settings, error: 'Remote access failed to start: $e');
    }
  }
}

Future<void> _startLanPushReceiver({
  required LoggingService logger,
  required String appVersion,
  required int appBuildNumber,
}) async {
  try {
    var isReceivingLanPush = false;
    final pushSecret = await _getOrCreatePushSecret(logger);
    final lanPushReceiver = LanPushReceiver(
      currentVersion: appVersion,
      currentBuildNumber: appBuildNumber,
      pushSecret: pushSecret,
    );
    lanPushReceiver.onUpdateReceived = (manifest, stagingPath) {
      isReceivingLanPush = false;
      logger.info(
        'Update received via LAN push',
        source: _logSource,
        fields: {'version': manifest.version},
      );
      LanPushNotifier.notifyUpdateReceived(manifest, stagingPath);
    };
    lanPushReceiver.onProgress = (received, total, progress, message) {
      isReceivingLanPush = total > 0 && received < total;
      logger.debug(
        'LAN push progress',
        source: _logSource,
        fields: {
          'progress_pct': (progress * 100).toStringAsFixed(1),
          'received': received,
          'total': total,
          'message': message,
        },
      );
      LanPushNotifier.notifyProgress(received, total, progress, message);
    };
    lanPushReceiver.onError = (error) {
      isReceivingLanPush = false;
      logger.error(
        'LAN push error',
        source: _logSource,
        fields: {'error': error},
      );
      LanPushNotifier.notifyError(error);
    };
    await lanPushReceiver.startServer();
    logger.info('LAN push receiver started on port 45680', source: _logSource);

    await UpdatePushDiscovery.startResponding(
      name: 'Nightshade',
      version: appVersion,
      buildNumber: appBuildNumber,
      isReceivingCallback: () => isReceivingLanPush,
    );
    logger.info('Update push discovery responder started', source: _logSource);
  } catch (e) {
    logger.warning(
      'LAN push receiver failed',
      source: _logSource,
      fields: {'error': '$e'},
    );
  }
}

/// Initialise the global catalog manager. Failures are non-fatal — the rest
/// of the GUI can still operate without local catalog data — but they are
/// logged as errors so the operator knows why catalog-backed UI is empty.
Future<void> initialiseCatalogManager(LoggingService logger) async {
  try {
    final appDataDir = await getApplicationSupportDirectory();
    final catalogDir = path.join(appDataDir.path, 'catalogs');
    await CatalogManager.instance.initialize(catalogDir);
    logger.info('Catalog manager initialised', source: _logSource);
  } catch (e) {
    logger.error(
      'Failed to initialise catalog manager',
      source: _logSource,
      fields: {'error': '$e'},
    );
  }
}

/// Resolve the "start minimized" setting by reading directly from the
/// settings DAO before any Riverpod-listening widget exists. Errors here
/// degrade to "do not minimise" because the alternative is a hidden window
/// with no way to surface it.
Future<bool> shouldStartMinimized(ProviderContainer container) async {
  final logger = container.read(loggingServiceProvider);
  try {
    final dao = container.read(settingsDaoProvider);
    final value = await dao.getSetting('start_minimized');
    return value == 'true';
  } catch (e) {
    logger.warning(
      'Failed to read start_minimized setting; defaulting to false',
      source: _logSource,
      fields: {'error': '$e'},
    );
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
Future<String> _getOrCreateRemoteAccessToken(LoggingService logger) async {
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
  final token =
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  await tokenFile.parent.create(recursive: true);
  await tokenFile.writeAsString(token);
  logger.info(
    'Generated new remote-access bearer token. Pair via the dashboard or '
    'copy the token from this file to configure mobile/CLI clients.',
    source: _logSource,
    fields: {'token_path': tokenFile.path},
  );
  return token;
}

/// Load or generate the LAN push authentication secret. Persisted in the app
/// data directory so it survives restarts. The same secret must be configured
/// on the push tool (dev machine) to authenticate.
Future<String> _getOrCreatePushSecret(LoggingService logger) async {
  final appData = await getApplicationSupportDirectory();
  final secretFile = File(path.join(appData.path, 'push_secret.txt'));

  if (await secretFile.exists()) {
    final secret = (await secretFile.readAsString()).trim();
    if (secret.isNotEmpty) {
      return secret;
    }
  }

  final secret = LanPushReceiver.generatePushSecret();
  await secretFile.parent.create(recursive: true);
  await secretFile.writeAsString(secret);
  logger.info(
    'Generated new LAN push secret. Configure this on the push tool.',
    source: _logSource,
    fields: {'secret_path': secretFile.path},
  );
  return secret;
}
