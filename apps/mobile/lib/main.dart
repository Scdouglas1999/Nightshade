import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_app/nightshade_app.dart';
import 'package:nightshade_app/localization/nightshade_localizations.dart';
// Hide nightshade_core's NotificationService — the mobile-side service of
// the same name owns local-notification deep-linking (audit §3.8).
import 'package:nightshade_core/nightshade_core.dart' hide NotificationService;
import 'package:nightshade_webrtc/nightshade_webrtc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/qr_scanner_screen.dart';
import 'services/mobile_preferences.dart';
import 'services/mobile_sequence_hooks.dart';
import 'services/network_service.dart';
import 'services/notification_service.dart';
import 'widgets/checkpoint_resume_dialog.dart';

void main() async {
  developer.log('Starting Nightshade...', name: 'Main', level: 800);
  WidgetsFlutterBinding.ensureInitialized();

  // Audit §3.13: respect the user's immersive-mode preference. Default is
  // leanBack so the system clock and battery indicator remain visible
  // during long sequences; users who want full-screen can opt in.
  if (Platform.isAndroid) {
    final prefs = await SharedPreferences.getInstance();
    final immersiveSticky = MobilePreferences(prefs).androidImmersiveSticky;
    SystemChrome.setEnabledSystemUIMode(
      immersiveSticky ? SystemUiMode.immersiveSticky : SystemUiMode.leanBack,
      overlays: immersiveSticky ? const [] : SystemUiOverlay.values,
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

  /// How long the WebSocket can stay disconnected before we declare the
  /// session dead and route the user back to the connection screen. The
  /// backend's own reconnector backs off up to 30 s; we wait the full
  /// grace before kicking the user out so transient blips don't drop a
  /// running session.
  static const Duration _connectionGracePeriod = Duration(seconds: 30);

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

  @override
  void initState() {
    super.initState();
    // Automatically discover and connect on startup
    _autoConnect();
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
                current.connectionState ==
                    BackendConnectionState.connected) {
              return;
            }
            developer.log(
              'WebSocket disconnected for ${_connectionGracePeriod.inSeconds}s — declaring connection lost',
              name: 'Connection',
              level: 1000,
            );
            _stopConnectionMonitor();
            ref.read(backendProvider.notifier).disconnect();
            ref.read(connectionStaleProvider.notifier).state = false;
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
          _error =
              'No Nightshade server found.\n\nTry:\n- Scanning a QR code from desktop\n- Entering the host address manually\n- Checking that UDP 45679 and HTTP 8080 are allowed through the firewall';
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
      // Audit §3.7: do not persist last-server based on synthetic
      // metadata. Track whether the /api/info call actually returned
      // server-supplied fields; if it didn't, we still allow the user
      // to connect for this session but refuse to write the server to
      // disk (next launch should re-discover or re-prompt).
      final fetched =
          await EnhancedNightshadeDiscovery.fetchServerInfo(server);
      final enrichedServer = fetched ?? server;
      final compatibility = NightshadeServerCompatibility.check(
        enrichedServer.version,
      );
      if (!compatibility.isCompatible) {
        setState(() {
          _isDiscovering = false;
          _statusMessage = '';
          _error = compatibility.message;
        });
        return;
      }

      // Test connection first
      final isReachable =
          await EnhancedNightshadeDiscovery.testServerConnection(
        enrichedServer.host,
        enrichedServer.webPort,
        authToken: enrichedServer.authToken,
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

        // Update global backend state to use NetworkBackend
        ref.read(backendProvider.notifier).connect(
              enrichedServer.host,
              enrichedServer.webPort,
              authToken: enrichedServer.authToken,
            );

        // Start monitoring the WS heartbeat (audit §3.6)
        _startConnectionMonitor();

        ref.invalidate(appSettingsProvider);
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
    } catch (e) {
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
    final data = await Navigator.push<QrConnectionData>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );

    if (data == null) return;

    setState(() {
      _isDiscovering = true;
      _statusMessage = 'Connecting via QR code...';
      _error = null;
    });

    await _connectToServer(data.toDiscoveredServer());
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

    final authToken = _accessTokenController.text.trim().isEmpty
        ? null
        : _accessTokenController.text.trim();

    setState(() {
      _isDiscovering = true;
      _error = null;
      _statusMessage = 'Connecting to $host:$port...';
    });

    final server = DiscoveredServer(
      name: 'Nightshade Server',
      host: host,
      webPort: port,
      signalingPort: 45678,
      version: '2.0.0',
      mode: 'headless',
      authToken: authToken,
    );

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
              if (context.mounted) {
                final colors = Theme.of(context).extension<NightshadeColors>();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to resume: $e'),
                    backgroundColor:
                        colors?.error ?? Theme.of(context).colorScheme.error,
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
    _stopConnectionMonitor();
    _ipController.dispose();
    _accessTokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    try {
      final themeMode = ref.watch(themeModeProvider);

      // Handle disconnection from Settings — if the backend becomes
      // DisconnectedBackend, return to the connection screen. Listening
      // (instead of watching+addPostFrameCallback in build) avoids the
      // build-time setState cycle flagged in audit §3.10.
      ref.listen<NightshadeBackend>(backendProvider, (previous, next) {
        if (!mounted) return;
        if (_connectedServer != null &&
            next is DisconnectedBackend &&
            !_skippedConnection) {
          setState(() {
            _connectedServer = null;
            _error = null;
            _statusMessage = '';
          });
        }
      });

      // If not connected and not skipped, show connection screen
      if (_connectedServer == null && !_skippedConnection) {
        return MaterialApp(
          title: 'Nightshade',
          debugShowCheckedModeBanner: false,
          theme: NightshadeTheme.light,
          darkTheme: NightshadeTheme.dark,
          themeMode: themeMode,
          localizationsDelegates:
              NightshadeLocalizations.localizationsDelegates,
          supportedLocales: NightshadeLocalizations.supportedLocales,
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

          // Wire notification taps into go_router (audit §3.8). The router
          // is created lazily by `appRouterProvider`; reading it here also
          // ensures it exists before a notification can fire.
          final router = ref.watch(appRouterProvider);
          NotificationService().setNavigator((location) {
            router.go(location);
          });

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
        localizationsDelegates: NightshadeLocalizations.localizationsDelegates,
        supportedLocales: NightshadeLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    NightshadeLocalizations.of(context)
                        .text('mobileErrorLoadingApp'),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
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
                    child: Text(
                      NightshadeLocalizations.of(context).text('mobileRetry'),
                    ),
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
        final l10n = context.l10n;
        final theme = Theme.of(context);
        final colors = theme.extension<NightshadeColors>();

        // If colors extension not available, use default Material colors
        final bgColor = colors?.background ?? theme.scaffoldBackgroundColor;
        final surfaceColor = colors?.surface ?? theme.cardColor;
        final textColor = colors?.textPrimary ??
            theme.textTheme.bodyLarge?.color ??
            theme.colorScheme.onSurface;
        final textSecondary = colors?.textSecondary ??
            theme.textTheme.bodyMedium?.color ??
            theme.colorScheme.onSurfaceVariant;
        final borderColor = colors?.border ?? theme.colorScheme.outlineVariant;
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
                      colors: [
                        primaryColor,
                        primaryColor.withValues(alpha: 0.7)
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.auto_awesome,
                    size: 16,
                    color: theme.colorScheme.onPrimary,
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
                    borderRadius: BorderRadius.circular(8),
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
                            l10n.text('mobileNotConnected'),
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
                            color: errorColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: errorColor.withValues(alpha: 0.3)),
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
                      NightshadeButton(
                        onPressed: () {
                          setState(() {
                            _showManualEntry = true;
                            _error = null;
                          });
                        },
                        icon: Icons.edit_location_alt,
                        label: l10n.text('mobileEnterIp'),
                        variant: ButtonVariant.ghost,
                        size: ButtonSize.small,
                      ),
                      const SizedBox(width: 8),
                      NightshadeButton(
                        onPressed: _scanQrCode,
                        icon: Icons.qr_code_scanner,
                        label: l10n.text('mobileScanQr'),
                        variant: ButtonVariant.ghost,
                        size: ButtonSize.small,
                      ),
                    ],
                  ),

                // Manual IP entry field
                if (_showManualEntry) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _ipController,
                    decoration: InputDecoration(
                      labelText: l10n.text('mobileServerIpAddress'),
                      hintText: '192.168.1.100:8080',
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
                  TextField(
                    controller: _accessTokenController,
                    obscureText: !_accessTokenVisible,
                    decoration: InputDecoration(
                      labelText: 'Access Token',
                      hintText: 'Optional for paired or protected hosts',
                      prefixIcon: const Icon(Icons.vpn_key),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _accessTokenVisible
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        tooltip: _accessTokenVisible
                            ? 'Hide access token'
                            : 'Show access token',
                        onPressed: () {
                          setState(() {
                            _accessTokenVisible = !_accessTokenVisible;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: surfaceColor,
                    ),
                    autocorrect: false,
                    enableSuggestions: false,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: NightshadeButton(
                          onPressed: () {
                            setState(() {
                              _showManualEntry = false;
                            });
                          },
                          label: l10n.text('cancel'),
                          variant: ButtonVariant.outline,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: NightshadeButton(
                          onPressed: _connectManually,
                          label: l10n.text('connect'),
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
                                : l10n.text('mobileSearchingForServer'),
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
                  SizedBox(
                    width: double.infinity,
                    child: NightshadeButton(
                      onPressed: _autoConnect,
                      icon: Icons.search,
                      label: l10n.text('searchForServer'),
                      size: ButtonSize.large,
                    ),
                  ),

                if (!_isDiscovering && !_showManualEntry) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _skipConnection,
                    child: Text(
                      l10n.text('mobileSkipConnection'),
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
                    color: surfaceColor.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
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
                            l10n.text('mobileHowToConnect'),
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
                        l10n.text('mobileHowToConnectSteps'),
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
