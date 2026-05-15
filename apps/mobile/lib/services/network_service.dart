import 'dart:async';
import 'dart:developer' as developer;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:nightshade_webrtc/nightshade_webrtc.dart';

/// Network connection status
enum NetworkStatus {
  connected,
  disconnected,
  reconnecting,
}

/// Network service state
class NetworkServiceState {
  final NetworkStatus status;
  final List<ConnectivityResult> connectivityResults;
  final DiscoveredServer? connectedServer;
  final String? statusMessage;

  const NetworkServiceState({
    required this.status,
    required this.connectivityResults,
    this.connectedServer,
    this.statusMessage,
  });

  bool get hasWifi => connectivityResults.contains(ConnectivityResult.wifi);
  bool get hasMobile => connectivityResults.contains(ConnectivityResult.mobile);
  bool get hasConnection => connectivityResults.isNotEmpty &&
      !connectivityResults.every((r) => r == ConnectivityResult.none);

  NetworkServiceState copyWith({
    NetworkStatus? status,
    List<ConnectivityResult>? connectivityResults,
    DiscoveredServer? connectedServer,
    String? statusMessage,
    bool clearServer = false,
  }) {
    return NetworkServiceState(
      status: status ?? this.status,
      connectivityResults: connectivityResults ?? this.connectivityResults,
      connectedServer: clearServer ? null : (connectedServer ?? this.connectedServer),
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}

/// Network service for monitoring connectivity and managing server connections
class NetworkService {
  static final NetworkService _instance = NetworkService._internal();
  factory NetworkService() => _instance;
  NetworkService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<dynamic>? _connectivitySubscription;

  final _stateController = StreamController<NetworkServiceState>.broadcast();
  NetworkServiceState _state = const NetworkServiceState(
    status: NetworkStatus.disconnected,
    connectivityResults: [],
  );

  Stream<NetworkServiceState> get stateStream => _stateController.stream;
  NetworkServiceState get currentState => _state;

  bool _isInitialized = false;
  DiscoveredServer? _lastKnownServer;
  Timer? _reconnectTimer;

  /// Initialize the network service
  Future<void> initialize() async {
    if (_isInitialized) {
      developer.log('Already initialized',
          name: 'NetworkService', level: 800);
      return;
    }

    developer.log('Initializing...', name: 'NetworkService', level: 800);

    // Load last known server
    _lastKnownServer = await EnhancedNightshadeDiscovery.loadLastServer();
    if (_lastKnownServer != null) {
      developer.log(
        'Loaded last known server: ${_lastKnownServer!.name}',
        name: 'NetworkService',
        level: 800,
      );
    }

    // Get initial connectivity status
    final connectivityResult = await _connectivity.checkConnectivity();
    // In connectivity_plus 5.0.0, checkConnectivity returns ConnectivityResult
    // In 6.0.0+, it returns List<ConnectivityResult>
    List<ConnectivityResult> connectivityResults;
    if (connectivityResult is List) {
      connectivityResults = (connectivityResult as List).cast<ConnectivityResult>();
    } else {
      connectivityResults = [connectivityResult];
    }
    _updateState(_state.copyWith(
      connectivityResults: connectivityResults,
      statusMessage: _getConnectivityMessage(connectivityResults),
    ));

    // Listen for connectivity changes
    // In 5.0.0, stream emits ConnectivityResult
    // In 6.0.0+, stream emits List<ConnectivityResult>
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (result) {
        List<ConnectivityResult> results;
        if (result is List) {
          results = (result as List).cast<ConnectivityResult>();
        } else {
          results = [result];
        }
        _onConnectivityChanged(results);
      },
      onError: (error) {
        // Caught + degraded: stream errors are non-fatal but we lose
        // connectivity-change events until the OS re-emits. Warn so the
        // gap is visible if reconnects start failing.
        developer.log(
          'Connectivity stream error: $error',
          name: 'NetworkService',
          level: 900,
        );
      },
    );

    _isInitialized = true;
    developer.log('Initialized', name: 'NetworkService', level: 800);

    // Try to reconnect to last server if we have WiFi
    if (_state.hasWifi && _lastKnownServer != null) {
      await _attemptReconnect();
    }
  }

  /// Dispose of the network service
  Future<void> dispose() async {
    developer.log('Disposing...', name: 'NetworkService', level: 800);
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _stateController.close();
    _isInitialized = false;
  }

  /// Handle connectivity changes
  void _onConnectivityChanged(List<ConnectivityResult> results) {
    developer.log(
      'Connectivity changed: $results',
      name: 'NetworkService',
      level: 800,
    );

    final hadWifi = _state.hasWifi;
    final hasWifi = results.contains(ConnectivityResult.wifi);

    _updateState(_state.copyWith(
      connectivityResults: results,
      statusMessage: _getConnectivityMessage(results),
    ));

    // If we gained WiFi connection, try to reconnect
    if (!hadWifi && hasWifi) {
      developer.log(
        'WiFi connected, attempting to reconnect...',
        name: 'NetworkService',
        level: 800,
      );
      _attemptReconnect();
    }

    // If we lost WiFi, mark as disconnected
    if (hadWifi && !hasWifi) {
      // Lost transport — degraded UX, surface as warning.
      developer.log('WiFi lost', name: 'NetworkService', level: 900);
      _updateState(_state.copyWith(
        status: NetworkStatus.disconnected,
        statusMessage: 'WiFi connection lost',
        clearServer: true,
      ));
    }

    // Warn if using mobile data
    if (!hasWifi && results.contains(ConnectivityResult.mobile)) {
      developer.log(
        'Using mobile data',
        name: 'NetworkService',
        level: 900,
      );
      _updateState(_state.copyWith(
        statusMessage: 'Connected via mobile data (may use data)',
      ));
    }
  }

  /// Get connectivity status message
  String _getConnectivityMessage(List<ConnectivityResult> results) {
    if (results.isEmpty || results.every((r) => r == ConnectivityResult.none)) {
      return 'No network connection';
    }

    if (results.contains(ConnectivityResult.wifi)) {
      return 'Connected via WiFi';
    }

    if (results.contains(ConnectivityResult.mobile)) {
      return 'Connected via mobile data';
    }

    if (results.contains(ConnectivityResult.ethernet)) {
      return 'Connected via Ethernet';
    }

    return 'Network available';
  }

  /// Attempt to reconnect to last known server
  Future<void> _attemptReconnect() async {
    if (_lastKnownServer == null) {
      developer.log(
        'No last known server to reconnect to',
        name: 'NetworkService',
        level: 800,
      );
      return;
    }

    _updateState(_state.copyWith(
      status: NetworkStatus.reconnecting,
      statusMessage: 'Reconnecting to ${_lastKnownServer!.name}...',
    ));

    try {
      // Test if server is reachable
      final isReachable = await EnhancedNightshadeDiscovery.testServerConnection(
        _lastKnownServer!.host,
        _lastKnownServer!.webPort,
        timeout: const Duration(seconds: 3),
      );

      if (isReachable) {
        developer.log(
          'Reconnected to ${_lastKnownServer!.name}',
          name: 'NetworkService',
          level: 800,
        );
        _updateState(_state.copyWith(
          status: NetworkStatus.connected,
          connectedServer: _lastKnownServer,
          statusMessage: 'Connected to ${_lastKnownServer!.name}',
        ));
      } else {
        // Caught + degraded path — reconnect failed, retry scheduled.
        developer.log(
          'Server not reachable, will retry...',
          name: 'NetworkService',
          level: 900,
        );
        _updateState(_state.copyWith(
          status: NetworkStatus.disconnected,
          statusMessage: 'Server not found on network',
        ));

        // Schedule retry
        _scheduleReconnect();
      }
    } catch (e, st) {
      // Caught + retry scheduled — log as severe so the failure chain is
      // attributable in DevTools even though we degrade gracefully.
      developer.log(
        'Reconnect error: $e',
        name: 'NetworkService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      _updateState(_state.copyWith(
        status: NetworkStatus.disconnected,
        statusMessage: 'Failed to reconnect: $e',
      ));

      // Schedule retry
      _scheduleReconnect();
    }
  }

  /// Schedule a reconnection attempt
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 10), () {
      if (_state.hasWifi && _lastKnownServer != null) {
        _attemptReconnect();
      }
    });
  }

  /// Manually trigger server rediscovery
  Future<DiscoveredServer?> rediscoverServer() async {
    if (!_state.hasConnection) {
      developer.log(
        'No network connection for discovery',
        name: 'NetworkService',
        level: 900,
      );
      return null;
    }

    _updateState(_state.copyWith(
      status: NetworkStatus.reconnecting,
      statusMessage: 'Searching for servers...',
    ));

    try {
      final server = await EnhancedNightshadeDiscovery.discoverWithFallback(
        onStatus: (status) {
          _updateState(_state.copyWith(statusMessage: status));
        },
      );

      if (server != null) {
        await connectToServer(server);
        return server;
      } else {
        _updateState(_state.copyWith(
          status: NetworkStatus.disconnected,
          statusMessage: 'No servers found',
        ));
        return null;
      }
    } catch (e, st) {
      // Caught + surfaced to UI via statusMessage; severe so the underlying
      // error chain is preserved.
      developer.log(
        'Discovery error: $e',
        name: 'NetworkService',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      _updateState(_state.copyWith(
        status: NetworkStatus.disconnected,
        statusMessage: 'Discovery failed: $e',
      ));
      return null;
    }
  }

  /// Connect to a specific server
  Future<void> connectToServer(DiscoveredServer server) async {
    developer.log(
      'Connecting to ${server.name} at ${server.host}:${server.webPort}',
      name: 'NetworkService',
      level: 800,
    );

    // Save as last known server
    await EnhancedNightshadeDiscovery.saveLastServer(server);
    _lastKnownServer = server;

    _updateState(_state.copyWith(
      status: NetworkStatus.connected,
      connectedServer: server,
      statusMessage: 'Connected to ${server.name}',
    ));
  }

  /// Disconnect from current server
  Future<void> disconnect() async {
    developer.log(
      'Disconnecting from server',
      name: 'NetworkService',
      level: 800,
    );

    // Clear saved server
    await EnhancedNightshadeDiscovery.clearLastServer();
    _lastKnownServer = null;

    _updateState(_state.copyWith(
      status: NetworkStatus.disconnected,
      connectedServer: null,
      statusMessage: 'Disconnected',
      clearServer: true,
    ));

    // Cancel any reconnection attempts
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  /// Update state and notify listeners
  void _updateState(NetworkServiceState newState) {
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(_state);
    }
  }

  /// Check if currently connected to a server
  bool get isConnected => _state.status == NetworkStatus.connected;

  /// Get current server
  DiscoveredServer? get currentServer => _state.connectedServer;

  /// Check if WiFi is available
  bool get hasWifi => _state.hasWifi;

  /// Check if any network connection is available
  bool get hasConnection => _state.hasConnection;
}
