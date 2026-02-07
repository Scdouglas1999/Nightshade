import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge;
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

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
///   --require-auth        Generate a random token
///
///   Environment variables:
///   NIGHTSHADE_AUTH_TOKEN  Authentication token
///   NIGHTSHADE_PORT        Server port (default: 8080)
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
      requireAuth: authConfig.requireAuth,
      port: authConfig.port,
    );
    runtimeLogger.info('Headless API server started',
        source: _headlessLogSource);

    debugPrint('\nNightshade is running in headless mode.');
    debugPrint('Press Ctrl+C to stop.\n');

    ProcessSignal.sigint.watch().listen((_) async {
      logger?.info('Received SIGINT, shutting down',
          source: _headlessLogSource);
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
  } catch (e) {
    debugPrint('Failed to initialize catalog manager: $e');
  }
}

class _AuthConfig {
  final String? token;
  final bool requireAuth;
  final int port;

  _AuthConfig({this.token, this.requireAuth = false, this.port = 8080});
}

_AuthConfig _parseAuthConfig(List<String> args) {
  String? token;
  var requireAuth = false;
  var port = 8080;

  token = Platform.environment['NIGHTSHADE_AUTH_TOKEN'];
  if (Platform.environment['NIGHTSHADE_PORT'] != null) {
    port = int.tryParse(Platform.environment['NIGHTSHADE_PORT']!) ?? 8080;
  }

  for (final arg in args) {
    if (arg.startsWith('--auth-token=')) {
      token = arg.substring('--auth-token='.length);
    } else if (arg == '--require-auth') {
      requireAuth = true;
    } else if (arg.startsWith('--port=')) {
      port = int.tryParse(arg.substring('--port='.length)) ?? port;
    }
  }

  return _AuthConfig(token: token, requireAuth: requireAuth, port: port);
}

Future<HeadlessApiServer?> _startHeadlessServices(
  ProviderContainer container, {
  required LoggingService logger,
  String? authToken,
  bool requireAuth = false,
  int port = 8080,
}) async {
  try {
    container.read(databaseProvider);
    logger.info('Database initialized', source: _headlessLogSource);
  } catch (e) {
    logger.warning(
      'Database initialization failed: $e',
      source: _headlessLogSource,
    );
  }

  try {
    await _startDiscoveryServer(logger: logger, advertisedPort: port);
    logger.info(
      'Discovery server started on UDP port 45679 (advertising $port)',
      source: _headlessLogSource,
    );
  } catch (e) {
    logger.warning('Discovery server failed: $e', source: _headlessLogSource);
  }

  final apiServer = HeadlessApiServer(
    port: port,
    container: container,
    authToken: authToken,
    requireAuth: requireAuth,
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

      if (localIp != null) {
        debugPrint('\n  Mobile devices can connect to:');
        debugPrint('    http://$localIp:$port');
        if (apiServer.effectiveAuthToken != null) {
          debugPrint('\n  Authentication required:');
          debugPrint(
              '    Authorization: Bearer ${apiServer.effectiveAuthToken}');
        }
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
  _discoverySocket = await RawDatagramSocket.bind(
    InternetAddress.anyIPv4,
    45679,
  );

  _discoverySocket!.listen(
    (event) {
      if (event != RawSocketEvent.read) {
        return;
      }
      final datagram = _discoverySocket!.receive();
      if (datagram == null) {
        return;
      }
      final message = String.fromCharCodes(datagram.data);
      if (!message.startsWith('NIGHTSHADE_DISCOVER')) {
        return;
      }
      final response = 'NIGHTSHADE_SERVER:$advertisedPort';
      _discoverySocket!
          .send(response.codeUnits, datagram.address, datagram.port);
    },
    onError: (Object error, StackTrace stackTrace) {
      logger.error('Discovery socket error: $error',
          source: _headlessLogSource);
    },
  );
}
