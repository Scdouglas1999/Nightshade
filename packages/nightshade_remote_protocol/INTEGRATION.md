# WebRTC Security Integration Guide

This guide shows how to integrate the secure WebRTC system into Nightshade 2.0.

## Quick Start

### 1. Desktop Application Setup

```dart
import 'package:nightshade_remote_protocol/nightshade_remote_protocol.dart';
import 'package:uuid/uuid.dart';

class RemoteControlService {
  final PairingDatabase _database = PairingDatabase();
  late final TokenManager _tokenManager;
  late final SecureDiscovery _discovery;
  late final SecureSignalingServer _signaling;

  final String _serverId = const Uuid().v4();

  Future<void> initialize() async {
    _tokenManager = TokenManager(_database);
    _discovery = SecureDiscovery(_tokenManager, _serverId);
    _signaling = SecureSignalingServer(_tokenManager);

    // Start services
    await _discovery.startServer(
      signalingPort: 45678,
      mode: DiscoveryMode.pairedOnly,
    );
    await _signaling.start();

    print('Remote control services started');
  }

  Future<void> dispose() async {
    await _discovery.stopServer();
    await _signaling.stop();
  }
}
```

### 2. Start Pairing Mode (Desktop UI)

```dart
class RemoteControlProvider extends StateNotifier<RemoteControlState> {
  final TokenManager tokenManager;
  final SecureDiscovery discovery;

  Timer? _pairingTimer;

  Future<void> startPairing() async {
    // Enable pairing mode in discovery
    discovery.setMode(DiscoveryMode.pairing, signalingPort: 45678);

    // Generate pairing code
    final code = await tokenManager.startPairing();
    state = state.copyWith(
      pairingCode: code,
      expiresAt: DateTime.now().add(Duration(minutes: 5)),
    );

    // Auto-disable pairing mode after 5 minutes
    _pairingTimer?.cancel();
    _pairingTimer = Timer(Duration(minutes: 5), () {
      discovery.setMode(DiscoveryMode.pairedOnly, signalingPort: 45678);
      state = state.copyWith(pairingCode: null, expiresAt: null);
    });
  }

  void cancelPairing() {
    _pairingTimer?.cancel();
    discovery.setMode(DiscoveryMode.pairedOnly, signalingPort: 45678);
    state = state.copyWith(pairingCode: null, expiresAt: null);
  }
}
```

### 3. Mobile Application Setup

```dart
import 'package:nightshade_remote_protocol/nightshade_remote_protocol.dart';
import 'package:uuid/uuid.dart';

class MobileRemoteClient {
  final String deviceId = const Uuid().v4();
  final String deviceName = 'My Phone'; // Or get from device info

  String? _sessionToken;
  ChannelEncryption? _encryption;
  Socket? _connection;

  /// Discover servers in pairing mode
  Future<List<SecureDiscoveredServer>> discoverServers() async {
    return await SecureDiscovery.discoverPairingServers(
      timeout: Duration(seconds: 5),
    );
  }

  /// Pair with a server using pairing code
  Future<bool> pairWithServer({
    required String serverHost,
    required String pairingCode,
  }) async {
    // In a real implementation, you'd send this via HTTP/HTTPS
    // to the server's pairing endpoint
    // For now, this is a conceptual example

    final response = await http.post(
      Uri.parse('http://$serverHost:45678/pair'),
      body: jsonEncode({
        'pairingCode': pairingCode,
        'deviceId': deviceId,
        'deviceName': deviceName,
        'deviceType': 'mobile',
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      _sessionToken = data['sessionToken'];

      // Save session token for future connections
      await _saveSessionToken(serverHost, _sessionToken!);

      return true;
    }

    return false;
  }

  /// Connect to a paired server
  Future<bool> connect(String serverHost) async {
    if (_sessionToken == null) {
      _sessionToken = await _loadSessionToken(serverHost);
      if (_sessionToken == null) {
        throw Exception('Not paired with this server');
      }
    }

    // Initialize encryption
    _encryption = ChannelEncryption.fromToken(_sessionToken!);

    // Connect to signaling server
    _connection = await Socket.connect(serverHost, 45678);

    // Send authentication message (unencrypted)
    final authMessage = SignalingMessage(
      type: SignalingMessageType.authRequest,
      payload: {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'sessionToken': _sessionToken,
      },
    );

    final authData = utf8.encode(jsonEncode(authMessage.toJson()));
    _connection!.add(authData);

    // Wait for auth response
    final response = await _connection!.first;
    final responseStr = utf8.decode(response);
    final responseMsg = SignalingMessage.fromJson(jsonDecode(responseStr));

    if (responseMsg.type == SignalingMessageType.authResponse &&
        responseMsg.payload['success'] == true) {
      // Start listening for encrypted messages
      _connection!.listen(_handleMessage);
      return true;
    }

    return false;
  }

  void _handleMessage(Uint8List data) {
    try {
      // Decrypt message
      final jsonStr = _encryption!.decryptString(data);
      final message = SignalingMessage.fromJson(jsonDecode(jsonStr));

      // Handle message based on type
      switch (message.type) {
        case SignalingMessageType.ping:
          _sendPong();
          break;
        case SignalingMessageType.offer:
          _handleOffer(message.payload);
          break;
        // ... handle other message types
        default:
          print('Unhandled message type: ${message.type}');
      }
    } catch (e) {
      print('Error handling message: $e');
    }
  }

  void _sendPong() {
    _sendEncryptedMessage(SignalingMessageType.pong, {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _sendEncryptedMessage(SignalingMessageType type, Map<String, dynamic> payload) {
    if (_encryption == null || _connection == null) return;

    final message = SignalingMessage(type: type, payload: payload);
    final jsonStr = jsonEncode(message.toJson());
    final encrypted = _encryption!.encryptString(jsonStr);
    _connection!.add(encrypted);
  }

  Future<void> _saveSessionToken(String host, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('session_token_$host', token);
  }

  Future<String?> _loadSessionToken(String host) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('session_token_$host');
  }

  void dispose() {
    _connection?.close();
    _encryption?.dispose();
  }
}
```

## UI Integration

### Add Pairing Screen to Settings

```dart
// In your settings navigation
class SettingsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Settings')),
      body: ListView(
        children: [
          // ... other settings

          ListTile(
            leading: Icon(Icons.devices),
            title: Text('Remote Connection'),
            subtitle: Text('Manage paired devices'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => PairingScreen()),
              );
            },
          ),

          // ... more settings
        ],
      ),
    );
  }
}
```

### Add Pairing Flow to Mobile App

```dart
class PairingFlow extends StatefulWidget {
  @override
  _PairingFlowState createState() => _PairingFlowState();
}

class _PairingFlowState extends State<PairingFlow> {
  final _client = MobileRemoteClient();
  List<SecureDiscoveredServer>? _servers;
  final _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _discoverServers();
  }

  Future<void> _discoverServers() async {
    final servers = await _client.discoverServers();
    setState(() {
      _servers = servers;
    });
  }

  Future<void> _pair(String serverHost) async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      _showError('Please enter pairing code');
      return;
    }

    final success = await _client.pairWithServer(
      serverHost: serverHost,
      pairingCode: code,
    );

    if (success) {
      Navigator.pop(context);
      _showSuccess('Successfully paired!');
    } else {
      _showError('Invalid or expired pairing code');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Pair with Desktop')),
      body: Column(
        children: [
          if (_servers == null)
            CircularProgressIndicator()
          else if (_servers!.isEmpty)
            Text('No servers found in pairing mode')
          else
            Expanded(
              child: ListView.builder(
                itemCount: _servers!.length,
                itemBuilder: (context, index) {
                  final server = _servers![index];
                  return ListTile(
                    title: Text(server.host),
                    subtitle: Text('Port: ${server.signalingPort}'),
                    trailing: ElevatedButton(
                      onPressed: () => _showPairingDialog(server.host),
                      child: Text('Pair'),
                    ),
                  );
                },
              ),
            ),

          Padding(
            padding: EdgeInsets.all(16),
            child: OutlinedButton(
              onPressed: _discoverServers,
              child: Text('Refresh'),
            ),
          ),
        ],
      ),
    );
  }

  void _showPairingDialog(String serverHost) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Enter Pairing Code'),
        content: TextField(
          controller: _codeController,
          decoration: InputDecoration(
            labelText: 'Pairing Code',
            hintText: 'STAR-1234',
          ),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _pair(serverHost);
            },
            child: Text('Pair'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }
}
```

## Server-Side Pairing Endpoint

You'll need to add an HTTP endpoint for pairing (the signaling server only handles authenticated WebRTC connections):

```dart
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

class PairingServer {
  final TokenManager tokenManager;

  PairingServer(this.tokenManager);

  Future<void> start() async {
    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addHandler(_handleRequest);

    await io.serve(handler, 'localhost', 8080);
    print('Pairing HTTP server listening on port 8080');
  }

  Future<Response> _handleRequest(Request request) async {
    if (request.method == 'POST' && request.url.path == 'pair') {
      return await _handlePairing(request);
    }

    return Response.notFound('Not found');
  }

  Future<Response> _handlePairing(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final pairingCode = data['pairingCode'] as String?;
      final deviceId = data['deviceId'] as String?;
      final deviceName = data['deviceName'] as String?;
      final deviceType = data['deviceType'] as String? ?? 'mobile';

      if (pairingCode == null || deviceId == null || deviceName == null) {
        return Response(400, body: jsonEncode({
          'error': 'Missing required fields',
        }));
      }

      // Verify pairing code
      final result = await tokenManager.verifyPairing(
        pairingCode: pairingCode,
        deviceId: deviceId,
        deviceName: deviceName,
        deviceType: deviceType,
      );

      if (result == PairingResult.success) {
        // Get the session token for this device
        final device = await tokenManager.getActivePairedDevices()
            .then((devices) => devices.firstWhere((d) => d.deviceId == deviceId));

        return Response.ok(jsonEncode({
          'success': true,
          'sessionToken': device.sessionToken,
        }));
      } else {
        return Response(400, body: jsonEncode({
          'success': false,
          'error': result.name,
        }));
      }
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({
        'error': 'Internal server error',
      }));
    }
  }
}
```

## Testing

### Unit Tests

```dart
void main() {
  group('TokenManager', () {
    test('generates secure 32-byte tokens', () {
      final tokenManager = TokenManager(mockDatabase);
      final token = tokenManager.generateSecureToken();

      expect(token.length, equals(64)); // 32 bytes = 64 hex chars
    });

    test('pairing code format is correct', () {
      final tokenManager = TokenManager(mockDatabase);
      final token = tokenManager.generateSecureToken();
      final code = tokenManager.generatePairingCode(token);

      expect(code, matches(RegExp(r'^[A-Z]+-\d{4}$')));
    });

    test('constant-time comparison works', () {
      final tokenManager = TokenManager(mockDatabase);
      final token1 = 'a' * 64;
      final token2 = 'a' * 64;
      final token3 = 'b' * 64;

      // These should be constant-time
      expect(tokenManager._constantTimeCompare(token1, token2), isTrue);
      expect(tokenManager._constantTimeCompare(token1, token3), isFalse);
    });
  });

  group('ChannelEncryption', () {
    test('encrypts and decrypts correctly', () {
      final encryption = ChannelEncryption.fromToken('test-token');
      final plaintext = 'Hello, World!';

      final encrypted = encryption.encryptString(plaintext);
      final decrypted = encryption.decryptString(encrypted);

      expect(decrypted, equals(plaintext));
    });

    test('encrypted data has correct format', () {
      final encryption = ChannelEncryption.fromToken('test-token');
      final encrypted = encryption.encryptString('test');

      // Should have nonce (12 bytes) + ciphertext + tag (16 bytes)
      expect(encrypted.length, greaterThan(28));
    });

    test('tampering is detected', () {
      final encryption = ChannelEncryption.fromToken('test-token');
      final encrypted = encryption.encryptString('test');

      // Tamper with the data
      encrypted[20] ^= 0xFF;

      expect(
        () => encryption.decryptString(encrypted),
        throwsA(isA<EncryptionException>()),
      );
    });
  });
}
```

## Troubleshooting

### Pairing Code Not Working
- Check that pairing mode is enabled on desktop
- Verify code hasn't expired (5 minute limit)
- Ensure code is entered exactly as shown (case-sensitive)

### Discovery Not Finding Servers
- Check firewall settings (UDP port 45679)
- Ensure both devices on same network
- Try manual IP entry if broadcasts blocked

### Connection Drops
- Check network stability
- Verify heartbeat responses (30-second timeout)
- Look for firewall interference

### Performance Issues
- Reduce message size if possible
- Consider batching frequent updates
- Profile encryption overhead

## Production Checklist

- [ ] Generate unique server ID per installation
- [ ] Implement secure storage for session tokens
- [ ] Add audit logging for security events
- [ ] Configure appropriate timeouts
- [ ] Test on production network configuration
- [ ] Document pairing process for end users
- [ ] Implement certificate pinning (optional)
- [ ] Add rate limiting for pairing attempts
- [ ] Configure firewall rules
- [ ] Test device revocation flow

## Support

For questions or issues:
1. Check SECURITY.md for implementation details
2. Review code comments in source files
3. Test with example implementations above
4. Open issue on GitHub with reproduction steps
