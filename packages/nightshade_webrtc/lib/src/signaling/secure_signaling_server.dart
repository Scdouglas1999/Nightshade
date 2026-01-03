import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import '../auth/token_manager.dart';
import '../crypto/channel_encryption.dart';

/// Message types for secure signaling protocol
enum SignalingMessageType {
  // Authentication phase
  authRequest,
  authResponse,
  authChallenge,

  // WebRTC signaling
  offer,
  answer,
  candidate,

  // Connection management
  ping,
  pong,
  disconnect,

  // Errors
  error,
}

/// Secure signaling message
class SignalingMessage {
  final SignalingMessageType type;
  final Map<String, dynamic> payload;

  SignalingMessage({
    required this.type,
    required this.payload,
  });

  factory SignalingMessage.fromJson(Map<String, dynamic> json) {
    return SignalingMessage(
      type: SignalingMessageType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => SignalingMessageType.error,
      ),
      payload: json['payload'] as Map<String, dynamic>? ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'payload': payload,
    };
  }
}

/// Connection state for each client
class ClientConnection {
  final Socket socket;
  String? deviceId;
  String? deviceName;
  bool isAuthenticated = false;
  ChannelEncryption? encryption;
  DateTime connectedAt;
  DateTime lastActivity;

  ClientConnection(this.socket)
      : connectedAt = DateTime.now(),
        lastActivity = DateTime.now();

  void updateActivity() {
    lastActivity = DateTime.now();
  }

  bool get isTimedOut {
    final timeout = DateTime.now().difference(lastActivity);
    return timeout.inSeconds > 30; // 30 second timeout
  }
}

/// Secure WebRTC signaling server with authentication
class SecureSignalingServer {
  static const int _signalingPort = 45678;
  static const Duration _authTimeout = Duration(seconds: 10);
  static const Duration _heartbeatInterval = Duration(seconds: 15);

  final TokenManager _tokenManager;

  ServerSocket? _server;
  final Map<String, ClientConnection> _clients = {};

  final _offerController = StreamController<SignalingMessage>.broadcast();
  Stream<SignalingMessage> get onOffer => _offerController.stream;

  final _answerController = StreamController<SignalingMessage>.broadcast();
  Stream<SignalingMessage> get onAnswer => _answerController.stream;

  final _candidateController = StreamController<SignalingMessage>.broadcast();
  Stream<SignalingMessage> get onCandidate => _candidateController.stream;

  final _clientConnectedController = StreamController<String>.broadcast();
  Stream<String> get onClientConnected => _clientConnectedController.stream;

  final _clientDisconnectedController = StreamController<String>.broadcast();
  Stream<String> get onClientDisconnected =>
      _clientDisconnectedController.stream;

  Timer? _heartbeatTimer;

  SecureSignalingServer(this._tokenManager);

  // ============================================================================
  // Server Lifecycle
  // ============================================================================

  /// Start the secure signaling server
  Future<void> start() async {
    if (_server != null) {
      print('[SecureSignaling] Server is already running');
      return;
    }

    // Try multiple times with delays to handle TIME_WAIT states
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        _server = await ServerSocket.bind(
          InternetAddress.anyIPv4,
          _signalingPort,
          shared: true,
        );

        _server!.listen(_handleNewConnection);

        // Start heartbeat timer
        _heartbeatTimer = Timer.periodic(_heartbeatInterval, _sendHeartbeats);

        print('[SecureSignaling] Server started on port $_signalingPort');
        return;
      } catch (e) {
        if (attempt < 2) {
          await Future.delayed(Duration(seconds: attempt + 1));
          continue;
        }
        print('[SecureSignaling] Failed to start server after 3 attempts: $e');
        rethrow;
      }
    }
  }

  /// Stop the server
  Future<void> stop() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    // Disconnect all clients
    for (final client in _clients.values) {
      await client.socket.close();
    }
    _clients.clear();

    await _server?.close();
    _server = null;

    print('[SecureSignaling] Server stopped');
  }

  // ============================================================================
  // Connection Handling
  // ============================================================================

  void _handleNewConnection(Socket socket) {
    final connectionId = '${socket.remoteAddress.address}:${socket.remotePort}';
    print('[SecureSignaling] New connection from $connectionId');

    final client = ClientConnection(socket);
    _clients[connectionId] = client;

    // Set authentication timeout
    Timer(_authTimeout, () {
      if (!client.isAuthenticated) {
        print('[SecureSignaling] Authentication timeout for $connectionId');
        _sendError(socket, 'Authentication timeout');
        socket.close();
        _clients.remove(connectionId);
      }
    });

    // Handle incoming data
    socket.listen(
      (data) => _handleData(connectionId, data),
      onError: (error) {
        print('[SecureSignaling] Error from $connectionId: $error');
        _handleDisconnect(connectionId);
      },
      onDone: () => _handleDisconnect(connectionId),
      cancelOnError: true,
    );
  }

  void _handleDisconnect(String connectionId) {
    final client = _clients[connectionId];
    if (client != null) {
      if (client.isAuthenticated && client.deviceId != null) {
        print(
            '[SecureSignaling] Device ${client.deviceName} (${client.deviceId}) disconnected');
        _clientDisconnectedController.add(client.deviceId!);
      }
      client.socket.close();
      _clients.remove(connectionId);
    }
  }

  void _handleData(String connectionId, Uint8List data) async {
    final client = _clients[connectionId];
    if (client == null) return;

    client.updateActivity();

    try {
      String messageStr;

      // If authenticated, decrypt the message
      if (client.isAuthenticated && client.encryption != null) {
        messageStr = client.encryption!.decryptString(data);
      } else {
        messageStr = utf8.decode(data);
      }

      final json = jsonDecode(messageStr) as Map<String, dynamic>;
      final message = SignalingMessage.fromJson(json);

      // Handle message based on authentication state
      if (!client.isAuthenticated) {
        await _handleAuthMessage(connectionId, message);
      } else {
        await _handleSignalingMessage(connectionId, message);
      }
    } catch (e) {
      print('[SecureSignaling] Error handling data from $connectionId: $e');
      _sendError(client.socket, 'Invalid message format');
    }
  }

  // ============================================================================
  // Authentication
  // ============================================================================

  Future<void> _handleAuthMessage(
      String connectionId, SignalingMessage message) async {
    final client = _clients[connectionId];
    if (client == null) return;

    if (message.type != SignalingMessageType.authRequest) {
      _sendError(client.socket, 'Authentication required');
      return;
    }

    final deviceId = message.payload['deviceId'] as String?;
    final deviceName = message.payload['deviceName'] as String?;
    final sessionToken = message.payload['sessionToken'] as String?;

    if (deviceId == null || deviceName == null || sessionToken == null) {
      _sendError(client.socket, 'Missing authentication credentials');
      return;
    }

    // Verify session token
    final result = await _tokenManager.verifySessionToken(
      deviceId: deviceId,
      token: sessionToken,
    );

    if (result == TokenVerificationResult.valid) {
      // Authentication successful
      client.deviceId = deviceId;
      client.deviceName = deviceName;
      client.isAuthenticated = true;
      client.encryption = ChannelEncryption.fromToken(sessionToken);

      print(
          '[SecureSignaling] Device $deviceName ($deviceId) authenticated successfully');

      // Send auth response (unencrypted, but now client knows to encrypt)
      _sendAuthResponse(client.socket, success: true);

      // Notify listeners
      _clientConnectedController.add(deviceId);
    } else {
      // Authentication failed
      print(
          '[SecureSignaling] Authentication failed for $deviceId: ${result.name}');
      _sendAuthResponse(client.socket, success: false, reason: result.name);
      client.socket.close();
      _clients.remove(connectionId);
    }
  }

  void _sendAuthResponse(Socket socket,
      {required bool success, String? reason}) {
    final message = SignalingMessage(
      type: SignalingMessageType.authResponse,
      payload: {
        'success': success,
        if (reason != null) 'reason': reason,
      },
    );

    final data = utf8.encode(jsonEncode(message.toJson()));
    socket.add(data);
  }

  // ============================================================================
  // Signaling Messages
  // ============================================================================

  Future<void> _handleSignalingMessage(
      String connectionId, SignalingMessage message) async {
    final client = _clients[connectionId];
    if (client == null || !client.isAuthenticated) return;

    switch (message.type) {
      case SignalingMessageType.offer:
        _offerController.add(message);
        break;

      case SignalingMessageType.answer:
        _answerController.add(message);
        break;

      case SignalingMessageType.candidate:
        _candidateController.add(message);
        break;

      case SignalingMessageType.ping:
        _sendMessage(client.socket, client.encryption!, SignalingMessageType.pong, {});
        break;

      case SignalingMessageType.disconnect:
        _handleDisconnect(connectionId);
        break;

      default:
        print('[SecureSignaling] Unknown message type: ${message.type}');
    }
  }

  /// Send an encrypted message to a specific client
  void sendToClient(String deviceId, SignalingMessage message) {
    final client = _clients.values.firstWhere(
      (c) => c.deviceId == deviceId && c.isAuthenticated,
      orElse: () => throw Exception('Client $deviceId not found or not authenticated'),
    );

    _sendMessage(client.socket, client.encryption!, message.type, message.payload);
  }

  /// Broadcast a message to all authenticated clients
  void broadcast(SignalingMessage message) {
    for (final client in _clients.values) {
      if (client.isAuthenticated && client.encryption != null) {
        _sendMessage(client.socket, client.encryption!, message.type, message.payload);
      }
    }
  }

  void _sendMessage(
    Socket socket,
    ChannelEncryption encryption,
    SignalingMessageType type,
    Map<String, dynamic> payload,
  ) {
    try {
      final message = SignalingMessage(type: type, payload: payload);
      final jsonStr = jsonEncode(message.toJson());
      final encrypted = encryption.encryptString(jsonStr);
      socket.add(encrypted);
    } catch (e) {
      print('[SecureSignaling] Error sending message: $e');
    }
  }

  void _sendError(Socket socket, String error) {
    final message = SignalingMessage(
      type: SignalingMessageType.error,
      payload: {'error': error},
    );
    final data = utf8.encode(jsonEncode(message.toJson()));
    socket.add(data);
  }

  // ============================================================================
  // Heartbeat & Cleanup
  // ============================================================================

  void _sendHeartbeats(Timer timer) {
    final now = DateTime.now();
    final toRemove = <String>[];

    for (final entry in _clients.entries) {
      final client = entry.value;

      if (client.isTimedOut) {
        print(
            '[SecureSignaling] Client ${entry.key} timed out (no activity for 30s)');
        toRemove.add(entry.key);
      } else if (client.isAuthenticated && client.encryption != null) {
        // Send ping to authenticated clients
        _sendMessage(
          client.socket,
          client.encryption!,
          SignalingMessageType.ping,
          {'timestamp': now.millisecondsSinceEpoch},
        );
      }
    }

    // Remove timed out clients
    for (final id in toRemove) {
      _handleDisconnect(id);
    }
  }

  // ============================================================================
  // Utilities
  // ============================================================================

  /// Get all currently connected device IDs
  List<String> getConnectedDevices() {
    return _clients.values
        .where((c) => c.isAuthenticated && c.deviceId != null)
        .map((c) => c.deviceId!)
        .toList();
  }

  /// Get local IP address for display to user
  Future<String?> getLocalIp() async {
    final interfaces = await NetworkInterface.list();
    for (final interface in interfaces) {
      for (final addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
          return addr.address;
        }
      }
    }
    return null;
  }

  void dispose() {
    stop();
    _offerController.close();
    _answerController.close();
    _candidateController.close();
    _clientConnectedController.close();
    _clientDisconnectedController.close();
  }
}
