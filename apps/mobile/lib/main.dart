import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_app/nightshade_app.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_webrtc/nightshade_webrtc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart';

import 'screens/qr_scanner_screen.dart';
import 'services/mobile_sequence_hooks.dart';
import 'services/network_service.dart';
import 'widgets/checkpoint_resume_dialog.dart';

void main() async {
  developer.log('Starting Nightshade...', name: 'Main', level: 800);
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Native Bridge (which handles RustLib initialization)
  try {
    await NativeBridge.init();
    developer.log('NativeBridge initialized successfully',
        name: 'Main', level: 800);
  } catch (e, stackTrace) {
    developer.log('Failed to initialize NativeBridge: $e',
        name: 'Main', level: 1000, error: e, stackTrace: stackTrace);
  }

  // Hide Android status bar for fullscreen experience
  if (Platform.isAndroid) {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );
  }

  // Initialize CatalogManager
  try {
    final appDir = await getApplicationDocumentsDirectory();
    await CatalogManager.instance.initialize(appDir.path);
  } catch (e) {
    developer.log('Failed to initialize CatalogManager: $e',
        name: 'Main', level: 1000);
  }

  // Initialize NetworkService for connectivity monitoring
  try {
    await NetworkService().initialize();
    developer.log('NetworkService initialized', name: 'Main');
  } catch (e) {
    developer.log('Failed to initialize NetworkService: $e',
        name: 'Main', level: 1000);
  }

  // Add error handling
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    developer.log('Flutter Error: ${details.exception}',
        name: 'Main',
        level: 1000,
        error: details.exception,
        stackTrace: details.stack);
  };

  runApp(
    const ProviderScope(
      child: NightshadeMobileApp(),
    ),
  );
}

class NightshadeMobileApp extends ConsumerStatefulWidget {
  const NightshadeMobileApp({super.key});

  @override
  ConsumerState<NightshadeMobileApp> createState() =>
      _NightshadeMobileAppState();
}

class _NightshadeMobileAppState extends ConsumerState<NightshadeMobileApp> {
  DiscoveredServer? _connectedServer;
  bool _isDiscovering = false;
  String? _error;
  String _statusMessage = '';
  final TextEditingController _ipController = TextEditingController(text: '');
  bool _showManualEntry = false;
  bool _skippedConnection = false;

  Timer? _connectionMonitorTimer;
  int _failedConnectionChecks = 0;

  @override
  void initState() {
    super.initState();
    // Automatically discover and connect on startup
    _autoConnect();
  }

  void _startConnectionMonitor(String host, int port) {
    _connectionMonitorTimer?.cancel();
    _failedConnectionChecks = 0;

    // Check every 5 seconds
    _connectionMonitorTimer =
        Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_connectedServer == null) {
        timer.cancel();
        return;
      }

      try {
        final isReachable =
            await EnhancedNightshadeDiscovery.testServerConnection(host, port);
        if (isReachable) {
          _failedConnectionChecks = 0;
        } else {
          _failedConnectionChecks++;
          developer.log('Failed connection check $_failedConnectionChecks/3',
              name: 'Connection', level: 900);
        }

        if (_failedConnectionChecks >= 3) {
          developer.log('Connection lost!', name: 'Connection', level: 1000);
          timer.cancel();

          if (mounted) {
            // Disconnect backend
            ref.read(backendProvider.notifier).disconnect();

            setState(() {
              _connectedServer = null;
              _isDiscovering = false;
              _error = 'Connection to server lost. Please reconnect.';
              _statusMessage = '';
            });
          }
        }
      } catch (e) {
        developer.log('Monitor error: $e', name: 'Connection', level: 1000);
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
        await EnhancedNightshadeDiscovery.saveLastServer(server);

        // Connect to server
        await _connectToServer(server);
      } else {
        developer.log('No server found via any method',
            name: 'Discovery', level: 900);
        setState(() {
          _isDiscovering = false;
          _statusMessage = '';
          _error =
              'No Nightshade server found.\n\nTry:\n• Scanning QR code from desktop\n• Entering IP address manually\n• Check firewall allows UDP 45679 & HTTP 8080';
        });
      }
    } catch (e) {
      developer.log('Discovery error: $e', name: 'Discovery', level: 1000);
      setState(() {
        _isDiscovering = false;
        _statusMessage = '';
        _error =
            'Discovery failed: $e\n\nTry entering the IP address manually or scan QR code.';
      });
    }
  }

  Future<void> _connectToServer(DiscoveredServer server) async {
    setState(() {
      _statusMessage = 'Connecting to ${server.name}...';
    });

    try {
      // Test connection first
      final isReachable =
          await EnhancedNightshadeDiscovery.testServerConnection(
        server.host,
        server.webPort,
      );

      if (isReachable) {
        developer.log('Connection successful!', name: 'Discovery', level: 800);

        // Update state
        setState(() {
          _connectedServer = server;
          _isDiscovering = false;
          _statusMessage = '';
        });

        // Update global backend state to use NetworkBackend
        ref.read(backendProvider.notifier).connect(server.host, server.webPort);

        // Start monitoring connection
        _startConnectionMonitor(server.host, server.webPort);

        // Sync location from server
        try {
          final backend = NetworkBackend(
            serverHost: server.host,
            serverPort: server.webPort,
          );
          final location = await backend.getLocation();
          if (location != null) {
            ref.read(appSettingsProvider.notifier).updateLocation(
                  latitude: location.latitude,
                  longitude: location.longitude,
                  elevation: location.elevation,
                );
            developer.log(
                'Synced location from server: ${location.latitude}, ${location.longitude}',
                name: 'Discovery');
          }
        } catch (e) {
          developer.log('Failed to sync location from server: $e',
              name: 'Discovery', level: 900);
        }
      } else {
        setState(() {
          _isDiscovering = false;
          _statusMessage = '';
          _error =
              'Could not connect to ${server.host}:${server.webPort}\n\nServer may be offline.';
        });
      }
    } catch (e) {
      setState(() {
        _isDiscovering = false;
        _statusMessage = '';
        _error = 'Connection error: $e';
      });
    }
  }

  Future<void> _scanQrCode() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );

    if (result != null) {
      final server = EnhancedNightshadeDiscovery.parseQrCode(result);
      if (server != null) {
        setState(() {
          _isDiscovering = true;
          _statusMessage = 'Connecting via QR code...';
          _error = null;
        });

        await EnhancedNightshadeDiscovery.saveLastServer(server);
        await _connectToServer(server);
      } else {
        setState(() {
          _error =
              'Invalid QR code. Please scan a Nightshade connection QR code.';
        });
      }
    }
  }

  Future<void> _connectManually() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      setState(() {
        _error = 'Please enter an IP address';
      });
      return;
    }

    setState(() {
      _isDiscovering = true;
      _error = null;
      _statusMessage = 'Connecting to $ip...';
    });

    final server = DiscoveredServer(
      name: 'Nightshade Server',
      host: ip,
      webPort: 8080,
      signalingPort: 45678,
      version: '2.0.0',
    );

    // Save for future reconnects
    await EnhancedNightshadeDiscovery.saveLastServer(server);
    await _connectToServer(server);
  }

  void _skipConnection() {
    setState(() {
      _skippedConnection = true;
      _isDiscovering = false;
      _error = null;
    });
    // Ensure backend is disconnected
    ref.read(backendProvider.notifier).disconnect();
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

        // Check if there's a checkpoint
        final hasCheckpoint = await executor.hasCheckpoint();
        if (!hasCheckpoint) return;

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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Sequence resumed from checkpoint'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to resume: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
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

  @override
  void dispose() {
    _connectionMonitorTimer?.cancel();
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    try {
      final themeMode = ref.watch(themeModeProvider);
      final backend = ref.watch(backendProvider);

      // Handle disconnection from Settings - if backend becomes disconnected, return to connection screen
      if (_connectedServer != null &&
          backend is DisconnectedBackend &&
          !_skippedConnection) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _connectedServer = null;
              _error = null;
              _statusMessage = '';
            });
          }
        });
      }

      // If not connected and not skipped, show connection screen
      if (_connectedServer == null && !_skippedConnection) {
        return MaterialApp(
          title: 'Nightshade',
          debugShowCheckedModeBanner: false,
          theme: NightshadeTheme.light,
          darkTheme: NightshadeTheme.dark,
          themeMode: themeMode,
          home: Builder(
            builder: (context) => _buildConnectionScreen(),
          ),
        );
      }

      // Once connected, show the full desktop UI
      // The backendProvider is already updated by _connect()
      return Consumer(
        builder: (context, ref, _) {
          // Activate location sync
          ref.watch(locationSyncProvider);

          // Initialize mobile sequence hooks for background operation support
          ref.watch(mobileSequenceHooksProvider);

          // Check for checkpoint on first connection
          _checkForCheckpoint(context, ref);

          return const NightshadeApp(isMobile: true);
        },
      );
    } catch (e, stackTrace) {
      // Fallback UI if something goes wrong
      developer.log('Error building app: $e',
          name: 'Main', level: 1000, error: e, stackTrace: stackTrace);
      return MaterialApp(
        title: 'Nightshade',
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text(
                    'Error Loading App',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Error: $e',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _connectedServer = null;
                        _error = null;
                        _isDiscovering = false;
                      });
                      _autoConnect();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
  }

  Widget _buildConnectionScreen() {
    // Safe color access with fallback
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final colors = theme.extension<NightshadeColors>();

        // If colors extension not available, use default Material colors
        final bgColor = colors?.background ?? theme.scaffoldBackgroundColor;
        final surfaceColor = colors?.surface ?? theme.cardColor;
        final textColor = colors?.textPrimary ??
            theme.textTheme.bodyLarge?.color ??
            Colors.black;
        final textSecondary = colors?.textSecondary ??
            theme.textTheme.bodyMedium?.color ??
            Colors.grey;
        final borderColor = colors?.border ?? Colors.grey.shade300;
        final primaryColor = colors?.primary ?? theme.colorScheme.primary;
        final errorColor = colors?.error ?? theme.colorScheme.error;

        return Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            backgroundColor: surfaceColor,
            title: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [primaryColor, primaryColor.withOpacity(0.7)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Nightshade',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Status card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: textSecondary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Not Connected',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: errorColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border:
                                Border.all(color: errorColor.withOpacity(0.3)),
                          ),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              fontSize: 12,
                              color: errorColor,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Connection options (Manual IP and QR scan)
                if (!_isDiscovering && !_showManualEntry)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _showManualEntry = true;
                            _error = null;
                          });
                        },
                        icon: const Icon(Icons.edit_location_alt),
                        label: const Text('Enter IP'),
                        style: TextButton.styleFrom(
                          foregroundColor: primaryColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: _scanQrCode,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Scan QR'),
                        style: TextButton.styleFrom(
                          foregroundColor: primaryColor,
                        ),
                      ),
                    ],
                  ),

                // Manual IP entry field
                if (_showManualEntry) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _ipController,
                    decoration: InputDecoration(
                      labelText: 'Server IP Address',
                      hintText: '192.168.1.100',
                      prefixIcon: const Icon(Icons.computer),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: surfaceColor,
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _showManualEntry = false;
                            });
                          },
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _connectManually,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Connect'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // Action buttons
                if (_isDiscovering)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        children: [
                          CircularProgressIndicator(color: primaryColor),
                          const SizedBox(height: 16),
                          Text(
                            _statusMessage.isNotEmpty
                                ? _statusMessage
                                : 'Searching for server...',
                            style: TextStyle(
                              fontSize: 14,
                              color: textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (!_showManualEntry)
                  ElevatedButton.icon(
                    onPressed: _autoConnect,
                    icon: const Icon(Icons.search),
                    label: const Text('Search for Server'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),

                if (!_isDiscovering && !_showManualEntry) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _skipConnection,
                    child: Text(
                      'Skip Connection (View UI Only)',
                      style: TextStyle(
                        color: textSecondary,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Instructions
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: surfaceColor.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 20, color: textSecondary),
                          const SizedBox(width: 8),
                          Text(
                            'How to Connect',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '1. Make sure Nightshade is running in headless mode on Windows or Raspberry Pi\n'
                        '2. Ensure both devices are on the same network\n'
                        '3. Tap "Search for Server" or wait for automatic discovery\n'
                        '4. The full desktop UI will load automatically',
                        style: TextStyle(
                          fontSize: 12,
                          color: textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
