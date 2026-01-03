import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';

import '../auth/token_manager.dart';

/// Discovery mode for the server
enum DiscoveryMode {
  /// Only respond to paired devices
  pairedOnly,

  /// Accept pairing requests (shows minimal info to unpaired devices)
  pairing,

  /// Completely hidden (no responses)
  hidden,
}

/// Discovered Nightshade server information (minimal for security)
class SecureDiscoveredServer {
  final String host;
  final int signalingPort;
  final String serverIdHash; // SHA-256 hash of server ID for verification
  final bool isPairingMode;

  SecureDiscoveredServer({
    required this.host,
    required this.signalingPort,
    required this.serverIdHash,
    required this.isPairingMode,
  });

  factory SecureDiscoveredServer.fromJson(Map<String, dynamic> json) {
    return SecureDiscoveredServer(
      host: json['host'] as String,
      signalingPort: json['signalingPort'] as int,
      serverIdHash: json['serverIdHash'] as String,
      isPairingMode: json['isPairingMode'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'host': host,
      'signalingPort': signalingPort,
      'serverIdHash': serverIdHash,
      'isPairingMode': isPairingMode,
    };
  }

  @override
  String toString() => 'Nightshade Server ($host:$signalingPort)';
}

/// Secure discovery service that only responds to paired devices or pairing requests
class SecureDiscovery {
  static const int _discoveryPort = 45679;
  static const String _discoveryMessage = 'NIGHTSHADE_SECURE_DISCOVERY';
  static const String _pairingDiscoveryMessage = 'NIGHTSHADE_PAIRING_REQUEST';
  static const String _responsePrefix = 'NIGHTSHADE_SECURE_RESPONSE:';

  final TokenManager _tokenManager;
  final String _serverId; // Unique server identifier

  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  DiscoveryMode _mode = DiscoveryMode.pairedOnly;

  SecureDiscovery(this._tokenManager, this._serverId);

  // ============================================================================
  // Server Side (Desktop)
  // ============================================================================

  /// Start secure broadcasting
  /// Only responds to discovery requests, doesn't broadcast continuously
  Future<void> startServer({
    required int signalingPort,
    DiscoveryMode mode = DiscoveryMode.pairedOnly,
  }) async {
    if (_socket != null) {
      print('[SecureDiscovery] Server already running');
      return;
    }

    _mode = mode;

    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      _discoveryPort,
      reuseAddress: true,
    );

    _socket!.broadcastEnabled = true;

    print('[SecureDiscovery] Secure discovery server started in ${mode.name} mode');

    // Listen for discovery requests
    _socket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = _socket!.receive();
        if (datagram != null) {
          _handleDiscoveryRequest(datagram, signalingPort);
        }
      }
    });

    // Optional: Broadcast in pairing mode only
    if (mode == DiscoveryMode.pairing) {
      _broadcastTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
        _broadcastPresence(signalingPort);
      });
    }
  }

  void _handleDiscoveryRequest(Datagram datagram, int signalingPort) async {
    try {
      final message = utf8.decode(datagram.data);

      // Check if this is a pairing request
      final isPairingRequest = message.startsWith(_pairingDiscoveryMessage);
      final isStandardRequest = message.startsWith(_discoveryMessage);

      if (!isPairingRequest && !isStandardRequest) {
        return; // Not a valid discovery message
      }

      // Extract device ID if present
      String? deviceId;
      if (message.contains(':')) {
        deviceId = message.split(':')[1];
      }

      // Determine if we should respond
      bool shouldRespond = false;

      switch (_mode) {
        case DiscoveryMode.hidden:
          shouldRespond = false;
          break;

        case DiscoveryMode.pairing:
          // Respond to all discovery requests in pairing mode
          shouldRespond = true;
          break;

        case DiscoveryMode.pairedOnly:
          // Only respond to paired devices
          if (deviceId != null) {
            final device = await _tokenManager
                .getActivePairedDevices()
                .then((devices) => devices.where((d) => d.deviceId == deviceId).firstOrNull);
            shouldRespond = device != null;
          } else if (isPairingRequest) {
            // Also respond to pairing requests (so they know we exist)
            shouldRespond = true;
          }
          break;
      }

      if (shouldRespond) {
        _sendResponse(datagram.address, signalingPort);
      }
    } catch (e) {
      print('[SecureDiscovery] Error handling discovery request: $e');
    }
  }

  void _sendResponse(InternetAddress address, int signalingPort) {
    try {
      final response = {
        'host': address.address,
        'signalingPort': signalingPort,
        'serverIdHash': _hashServerId(_serverId),
        'isPairingMode': _mode == DiscoveryMode.pairing,
      };

      final message = '$_responsePrefix${jsonEncode(response)}';
      final data = utf8.encode(message);

      _socket!.send(data, address, _discoveryPort);
    } catch (e) {
      // Ignore send errors
    }
  }

  void _broadcastPresence(int signalingPort) {
    try {
      final response = {
        'host': '0.0.0.0', // Will be replaced by receiver
        'signalingPort': signalingPort,
        'serverIdHash': _hashServerId(_serverId),
        'isPairingMode': true,
      };

      final message = '$_responsePrefix${jsonEncode(response)}';
      final data = utf8.encode(message);

      _socket!.send(data, InternetAddress('255.255.255.255'), _discoveryPort);
    } catch (e) {
      // Ignore broadcast errors
    }
  }

  /// Change the discovery mode
  void setMode(DiscoveryMode mode, {required int signalingPort}) {
    _mode = mode;

    // Stop broadcasting if not in pairing mode
    if (mode != DiscoveryMode.pairing) {
      _broadcastTimer?.cancel();
      _broadcastTimer = null;
    } else {
      // Start broadcasting if in pairing mode
      if (_broadcastTimer == null && _socket != null) {
        _broadcastTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
          _broadcastPresence(signalingPort);
        });
      }
    }

    print('[SecureDiscovery] Mode changed to ${mode.name}');
  }

  /// Stop the server
  Future<void> stopServer() async {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _socket?.close();
    _socket = null;
    print('[SecureDiscovery] Server stopped');
  }

  // ============================================================================
  // Client Side (Mobile)
  // ============================================================================

  /// Discover servers (for paired device)
  static Future<List<SecureDiscoveredServer>> discoverServers({
    String? deviceId,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final servers = <SecureDiscoveredServer>[];
    final seen = <String>{};

    try {
      print('[SecureDiscovery] Starting discovery...');

      // Create socket for receiving responses
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _discoveryPort,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;

      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram != null) {
            try {
              final message = utf8.decode(datagram.data);
              if (message.startsWith(_responsePrefix)) {
                final jsonStr = message.substring(_responsePrefix.length);
                final data = jsonDecode(jsonStr) as Map<String, dynamic>;

                final host = datagram.address.address;
                final key = '${host}:${data['signalingPort']}';

                if (!seen.contains(key)) {
                  seen.add(key);
                  final server = SecureDiscoveredServer(
                    host: host,
                    signalingPort: data['signalingPort'] as int,
                    serverIdHash: data['serverIdHash'] as String,
                    isPairingMode: data['isPairingMode'] as bool,
                  );
                  servers.add(server);
                  print('[SecureDiscovery] Found server: $host');
                }
              }
            } catch (e) {
              print('[SecureDiscovery] Error parsing response: $e');
            }
          }
        }
      });

      // Send discovery request with device ID if available
      final discoveryMsg = deviceId != null
          ? '$_discoveryMessage:$deviceId'
          : _discoveryMessage;
      final data = utf8.encode(discoveryMsg);
      socket.send(data, InternetAddress('255.255.255.255'), _discoveryPort);

      // Wait for responses
      await Future.delayed(timeout);
      socket.close();

      print('[SecureDiscovery] Discovery complete, found ${servers.length} servers');
      return servers;
    } catch (e) {
      print('[SecureDiscovery] Discovery error: $e');
      return servers;
    }
  }

  /// Discover servers in pairing mode (for unpaired device)
  static Future<List<SecureDiscoveredServer>> discoverPairingServers({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final servers = <SecureDiscoveredServer>[];
    final seen = <String>{};

    try {
      print('[SecureDiscovery] Looking for servers in pairing mode...');

      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _discoveryPort,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;

      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram != null) {
            try {
              final message = utf8.decode(datagram.data);
              if (message.startsWith(_responsePrefix)) {
                final jsonStr = message.substring(_responsePrefix.length);
                final data = jsonDecode(jsonStr) as Map<String, dynamic>;

                // Only include servers in pairing mode
                if (data['isPairingMode'] == true) {
                  final host = datagram.address.address;
                  final key = '${host}:${data['signalingPort']}';

                  if (!seen.contains(key)) {
                    seen.add(key);
                    final server = SecureDiscoveredServer(
                      host: host,
                      signalingPort: data['signalingPort'] as int,
                      serverIdHash: data['serverIdHash'] as String,
                      isPairingMode: true,
                    );
                    servers.add(server);
                    print('[SecureDiscovery] Found pairing server: $host');
                  }
                }
              }
            } catch (e) {
              print('[SecureDiscovery] Error parsing response: $e');
            }
          }
        }
      });

      // Send pairing discovery request
      final data = utf8.encode(_pairingDiscoveryMessage);
      socket.send(data, InternetAddress('255.255.255.255'), _discoveryPort);

      // Wait for responses
      await Future.delayed(timeout);
      socket.close();

      print(
          '[SecureDiscovery] Found ${servers.length} servers in pairing mode');
      return servers;
    } catch (e) {
      print('[SecureDiscovery] Discovery error: $e');
      return servers;
    }
  }

  // ============================================================================
  // Utility Methods
  // ============================================================================

  /// Hash server ID for public identification without revealing the actual ID
  static String _hashServerId(String serverId) {
    final bytes = utf8.encode(serverId);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16);
  }

  void dispose() {
    stopServer();
  }
}
