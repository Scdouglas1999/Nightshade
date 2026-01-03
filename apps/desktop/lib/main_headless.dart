import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge;
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'headless_api_server.dart';

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
void main() async {
  // Initialize Flutter bindings (required for async operations)
  WidgetsFlutterBinding.ensureInitialized();

  print('Nightshade 2.0 - Headless Mode');
  print('==============================');

  try {
    // Initialize the native bridge
    print('Initializing native bridge...');
    await bridge.NativeBridge.init();
    print('✓ Native bridge initialized');

    // Initialize catalog manager with app data directory
    print('Initializing catalog manager...');
    await _initializeCatalogManager();
    print('✓ Catalog manager initialized');

    // Create Riverpod container for dependency injection
    print('Initializing services...');
    final container = ProviderContainer();
    // Explicitly use local backend for headless server
    container.read(backendProvider.notifier).useLocalBackend();
    print('✓ Services initialized');

    // Start headless services
    print('Starting headless API server...');
    final apiServer = await _startHeadlessServices(container);
    print('✓ Headless API server started');

    print('\\nNightshade is running in headless mode.');
    print('Press Ctrl+C to stop.\\n');

    // Handle interrupt signal (works on Windows, Linux, macOS)
    ProcessSignal.sigint.watch().listen((signal) async {
      print('\\nShutting down...');
      await apiServer?.stop();
      container.dispose();
      exit(0);
    });
    
    // Also handle SIGTERM on Unix systems (Linux, macOS)
    if (Platform.isLinux || Platform.isMacOS) {
      ProcessSignal.sigterm.watch().listen((signal) async {
        print('\\nShutting down...');
        await apiServer?.stop();
        container.dispose();
        exit(0);
      });
    }

    // Set up event broadcasting to WebSocket clients
    final backend = container.read(backendProvider);
    backend.eventStream.listen((event) {
      apiServer?.broadcastEvent(event);
    });

    // Keep alive loop
    while (true) {
      await Future.delayed(const Duration(seconds: 1));
    }
  } catch (e, stackTrace) {
    print('Error starting headless mode: $e');
    print('Stack trace: $stackTrace');
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
    // Don't fail completely - catalogs are optional
  }
}

Future<HeadlessApiServer?> _startHeadlessServices(ProviderContainer container) async {
  // Initialize database for API access
  try {
    final _ = NightshadeDatabase();
    print('  ✓ Database initialized');
  } catch (e) {
    print('  ⚠ Database initialization failed: $e');
  }

  // Start UDP discovery server
  try {
    await _startDiscoveryServer();
    print('  ✓ Discovery server started on UDP port 45679');
  } catch (e) {
    print('  ⚠ Discovery server failed: $e');
  }

  // Start comprehensive API server
  final apiServer = HeadlessApiServer(
    port: 8080,
    container: container,
  );
  
  try {
    await apiServer.start();
    print('  ✓ API server started on port 8080');
    
    // Get local IP for user info
    try {
      final interfaces = await NetworkInterface.list();
      String? localIp;
      
      for (final interface in interfaces) {
        if (!interface.name.contains('lo') && !interface.name.contains('Loopback')) {
          for (final addr in interface.addresses) {
            if (addr.type == InternetAddressType.IPv4) {
              localIp = addr.address;
              break;
            }
          }
          if (localIp != null) break;
        }
      }
      
      if (localIp != null) {
        print('\\n  Mobile devices can connect to:');
        print('    http://$localIp:8080');
        print('');
      }
    } catch (e) {
      // Ignore IP detection errors
    }
    
    return apiServer;
  } catch (e) {
    print('  ⚠ API server failed to start: $e');
    return null;
  }
}

RawDatagramSocket? _discoverySocket;

Future<void> _startDiscoveryServer() async {
  _discoverySocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 45679);
  
  _discoverySocket!.listen((event) {
    if (event == RawSocketEvent.read) {
      final datagram = _discoverySocket!.receive();
      if (datagram != null) {
        final message = String.fromCharCodes(datagram.data);
        
        // Respond to discovery requests
        if (message.startsWith('NIGHTSHADE_DISCOVER')) {
          const response = 'NIGHTSHADE_SERVER:8080';
          _discoverySocket!.send(
            response.codeUnits,
            datagram.address,
            datagram.port,
          );
        }
      }
    }
  });
}
