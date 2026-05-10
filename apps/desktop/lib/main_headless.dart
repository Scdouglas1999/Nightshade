import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge;
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_webrtc/nightshade_webrtc.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'headless_api/auth_policy.dart';
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
///
///   Environment variables:
///   NIGHTSHADE_AUTH_TOKEN  Authentication token
///   NIGHTSHADE_VIEW_TOKEN  Optional read-only token
///   NIGHTSHADE_CONTROL_TOKEN
///                         Optional imaging-control token
///   NIGHTSHADE_PORT        Server port (default: 8080)
///   NIGHTSHADE_ALLOW_UNAUTHENTICATED_LAN=true
///                         Same as --allow-unauthenticated-lan
///   NIGHTSHADE_CORS_ORIGINS
///                         Comma-separated CORS allow-list (same effect as
///                         passing --cors-origin repeatedly).
void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint('Nightshade 2.0 - Headless Mode');
  debugPrint('==============================');

  LoggingService? logger;
  ProviderContainer? container;
  HeadlessApiServer? apiServer;

  try {
    debugPrint('Initializing native bridge...');
    await bridge.NativeBridge.init();
    debugPrint('[OK] Native bridge initialized');

    // Initialize profile and settings storage (must happen before any profile/settings access)
    debugPrint('Initializing profile and settings storage...');
    final appDir = await getApplicationDocumentsDirectory();
    final profileDir = path.join(appDir.path, 'Nightshade', 'profiles');
    await Directory(profileDir).create(recursive: true);
    await bridge.NativeBridge.apiInitProfileStorage(storagePath: profileDir);
    await bridge.NativeBridge.apiInitSettingsStorage(storagePath: profileDir);
    debugPrint('[OK] Profile and settings storage initialized');

    debugPrint('Initializing catalog manager...');
    await _initializeCatalogManager();
    debugPrint('[OK] Catalog manager initialized');

    debugPrint('Initializing services...');
    container = ProviderContainer();
    final runtimeLogger = container.read(loggingServiceProvider);
    logger = runtimeLogger;
    await runtimeLogger.initialize();
    container.read(backendProvider.notifier).useLocalBackend();
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
    );
    runtimeLogger.info('Headless API server started',
        source: _headlessLogSource);

    debugPrint('\nNightshade is running in headless mode.');
    debugPrint('Press Ctrl+C to stop.\n');

    ProcessSignal.sigint.watch().listen((_) async {
      logger?.info('Received SIGINT, shutting down',
          source: _headlessLogSource);
      _discoverySocket?.close();
      await apiServer?.stop();
      container?.dispose();
      exit(0);
    });

    if (Platform.isLinux || Platform.isMacOS) {
      ProcessSignal.sigterm.watch().listen((_) async {
        logger?.info(
          'Received SIGTERM, shutting down',
          source: _headlessLogSource,
        );
        _discoverySocket?.close();
        await apiServer?.stop();
        container?.dispose();
        exit(0);
      });
    }

    final backend = container.read(backendProvider);
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
    debugPrint('Error starting headless mode: $e');
    debugPrint('Stack trace: $stackTrace');
    await apiServer?.stop();
    container?.dispose();
    exit(1);
  }
}

Future<void> _initializeCatalogManager() async {
  try {
    final appDataDir = await getApplicationSupportDirectory();
    final catalogDir = path.join(appDataDir.path, 'catalogs');
    await CatalogManager.instance.initialize(catalogDir);
  } catch (e, stackTrace) {
    // Catalog is non-critical for headless operation (API/sequencer still work),
    // but log as error so it doesn't go unnoticed.
    debugPrint('[ERROR] Failed to initialize catalog manager: $e');
    debugPrint('[ERROR] Stack trace: $stackTrace');
  }
}

class _AuthConfig {
  final String? token;
  final bool requireAuth;
  final bool bindLocalOnly;
  final int port;
  final Map<String, HeadlessTokenScope> scopedTokens;
  final List<String> corsAllowedOrigins;

  _AuthConfig({
    this.token,
    this.requireAuth = false,
    this.bindLocalOnly = true,
    this.port = 8080,
    this.scopedTokens = const {},
    this.corsAllowedOrigins = const [],
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
    }
  }

  if (token != null && token.trim().isEmpty) {
    token = null;
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

Future<HeadlessApiServer?> _startHeadlessServices(
  ProviderContainer container, {
  required LoggingService logger,
  String? authToken,
  Map<String, HeadlessTokenScope> scopedAuthTokens = const {},
  bool requireAuth = false,
  bool bindLocalOnly = true,
  int port = 8080,
  List<String> corsAllowedOrigins = const [],
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

  if (!bindLocalOnly) {
    try {
      await _startDiscoveryServer(logger: logger, advertisedPort: port);
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

  final apiServer = HeadlessApiServer(
    port: port,
    container: container,
    authToken: authToken,
    scopedAuthTokens: scopedAuthTokens,
    requireAuth: requireAuth,
    bindLocalOnly: bindLocalOnly,
    corsAllowedOrigins: corsAllowedOrigins,
  );

  try {
    await apiServer.start();
    logger.info('API server started on port $port', source: _headlessLogSource);

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

      if (!bindLocalOnly && localIp != null) {
        debugPrint('\n  Mobile devices can connect to:');
        debugPrint('    http://$localIp:$port');
        if (apiServer.effectiveAuthToken != null) {
          debugPrint('\n  Authentication required:');
          debugPrint(
              '    Authorization: Bearer ${apiServer.effectiveAuthToken}');
        } else {
          debugPrint(
              '\n  WARNING: unauthenticated LAN control is enabled for this run.');
        }
        debugPrint('');
      } else {
        debugPrint('\n  Headless API is available on:');
        debugPrint('    http://127.0.0.1:$port');
        debugPrint(
            '  Add --require-auth or --auth-token to expose authenticated LAN access.');
        debugPrint('');
      }
    } catch (_) {
      // Best-effort local IP discovery only.
    }

    return apiServer;
  } catch (e) {
    logger.error('API server failed to start: $e', source: _headlessLogSource);
    return null;
  }
}

RawDatagramSocket? _discoverySocket;

Future<void> _startDiscoveryServer({
  required LoggingService logger,
  required int advertisedPort,
}) async {
  _discoverySocket = await NightshadeDiscovery.startBroadcasting(
    webPort: advertisedPort,
    signalingPort: advertisedPort,
    name: 'Nightshade Headless',
    version: '2.5.0',
  );
  logger.info(
    'Broadcasting headless server discovery beacons for port $advertisedPort',
    source: _headlessLogSource,
  );
}
