# WebRTC Security - Quick Start Guide

**5-Minute Integration Guide for Developers**

---

## Installation

Add to `pubspec.yaml`:
```yaml
dependencies:
  nightshade_webrtc: ^1.0.0
```

---

## Desktop Setup (3 steps)

### 1. Initialize
```dart
import 'package:nightshade_webrtc/nightshade_webrtc.dart';

final database = PairingDatabase();
final tokenManager = TokenManager(database);
final discovery = SecureDiscovery(tokenManager, 'unique-server-id');
final signaling = SecureSignalingServer(tokenManager);
```

### 2. Start Services
```dart
await discovery.startServer(
  signalingPort: 45678,
  mode: DiscoveryMode.pairedOnly, // Secure by default
);
await signaling.start();
```

### 3. Handle Pairing
```dart
// User clicks "Start Pairing" button
final code = await tokenManager.startPairing();
print('Show user: $code'); // e.g., "STAR-1234"

// Code expires in 5 minutes automatically

// After pairing, return to secure mode
discovery.setMode(DiscoveryMode.pairedOnly, signalingPort: 45678);
```

---

## Mobile Setup (3 steps)

### 1. Discover Servers
```dart
final servers = await SecureDiscovery.discoverPairingServers();
// Shows only servers in pairing mode
```

### 2. Pair with Server
```dart
// Send pairing request to server's HTTP endpoint
final response = await http.post(
  Uri.parse('http://${server.host}:8080/pair'),
  body: jsonEncode({
    'pairingCode': userEnteredCode,
    'deviceId': myDeviceId,
    'deviceName': myDeviceName,
  }),
);

final sessionToken = jsonDecode(response.body)['sessionToken'];
// Save this token for future connections
```

### 3. Connect
```dart
// Create encryption instance
final encryption = ChannelEncryption.fromToken(sessionToken);

// Connect to signaling server
final socket = await Socket.connect(server.host, 45678);

// Send auth message (unencrypted, first message only)
final authMsg = SignalingMessage(
  type: SignalingMessageType.authRequest,
  payload: {
    'deviceId': myDeviceId,
    'deviceName': myDeviceName,
    'sessionToken': sessionToken,
  },
);
socket.add(utf8.encode(jsonEncode(authMsg.toJson())));

// All subsequent messages are encrypted
final encrypted = encryption.encryptJson({'command': 'start'});
socket.add(base64Decode(encrypted));
```

---

## UI Integration

### Add to Settings Menu
```dart
ListTile(
  leading: Icon(Icons.devices),
  title: Text('Remote Connection'),
  onTap: () => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => PairingScreen()),
  ),
),
```

---

## Common Operations

### Check if Device is Paired
```dart
final device = await tokenManager.getActivePairedDevices()
    .then((devices) => devices.where((d) => d.deviceId == deviceId).firstOrNull);

if (device != null) {
  print('Device paired: ${device.deviceName}');
}
```

### Revoke a Device
```dart
await tokenManager.revokeDevice(deviceId);
```

### Send Encrypted Message
```dart
final encryption = ChannelEncryption.fromToken(sessionToken);
final encrypted = encryption.encryptJson({
  'type': 'command',
  'action': 'start_imaging',
  'target': 'M31',
});

socket.add(base64Decode(encrypted));
```

### Receive Encrypted Message
```dart
socket.listen((data) {
  final decrypted = encryption.decryptJson(base64Encode(data));
  print('Received: $decrypted');
});
```

---

## Security Checklist

Before deploying:

- [ ] Use unique server ID (UUID) per installation
- [ ] Store session tokens securely (SharedPreferences/Keychain)
- [ ] Enable pairing mode only when user requests it
- [ ] Return to `pairedOnly` mode after pairing
- [ ] Clean up expired sessions periodically
- [ ] Test on actual network (not just localhost)
- [ ] Configure firewall rules (UDP 45679, TCP 45678)

---

## Discovery Modes

| Mode | When to Use | Security |
|------|-------------|----------|
| `pairedOnly` | Normal operation | ⭐⭐⭐⭐⭐ High |
| `pairing` | Accepting new device | ⭐⭐⭐⭐ Medium |
| `hidden` | Maximum stealth | ⭐⭐⭐⭐⭐ Max |

---

## Troubleshooting

### Pairing Code Invalid
- Check code hasn't expired (5 minutes)
- Verify code entered correctly (case-sensitive)
- Ensure server is in pairing mode

### Can't Discover Server
- Check firewall allows UDP broadcasts (port 45679)
- Verify both devices on same network
- Try manual IP entry if broadcasts blocked

### Connection Drops
- Check network stability
- Verify heartbeat responses working
- Look for firewall interference

### Performance Issues
- Profile encryption overhead
- Check PBKDF2 isn't called per-message (should be once at pairing)
- Reduce message size if possible

---

## API Reference

### TokenManager
```dart
generateSecureToken() → String              // 32-byte random token
generatePairingCode(token) → String         // User-friendly code
startPairing() → Future<String>             // Begin 5-min pairing window
verifyPairing(...) → Future<PairingResult>  // Complete pairing
verifySessionToken(...) → Future<bool>      // Check subsequent connections
revokeDevice(deviceId) → Future<void>       // Block device
```

### ChannelEncryption
```dart
fromToken(sessionToken) → ChannelEncryption // Create from token
encrypt(data) → Uint8List                   // Encrypt bytes
decrypt(data) → Uint8List                   // Decrypt bytes
encryptJson(map) → String                   // Encrypt JSON → base64
decryptJson(base64) → Map                   // Decrypt base64 → JSON
```

### SecureSignalingServer
```dart
start() → Future<void>                      // Start server
stop() → Future<void>                       // Stop server
sendToClient(deviceId, message) → void      // Send to specific client
broadcast(message) → void                   // Send to all clients
```

### SecureDiscovery
```dart
startServer(...) → Future<void>             // Start discovery server
setMode(mode, ...) → void                   // Change discovery mode
stopServer() → Future<void>                 // Stop server
discoverServers(...) → Future<List>         // Find servers (client)
discoverPairingServers(...) → Future<List>  // Find pairing servers
```

---

## Message Types

### Authentication
- `authRequest` - Client → Server: Initial auth
- `authResponse` - Server → Client: Auth result

### WebRTC Signaling
- `offer` - WebRTC offer
- `answer` - WebRTC answer
- `candidate` - ICE candidate

### Connection Management
- `ping` - Server → Client: Heartbeat
- `pong` - Client → Server: Response
- `disconnect` - Graceful shutdown

### Errors
- `error` - Error notification

---

## Performance

| Operation | Time | Notes |
|-----------|------|-------|
| Token Generation | <1ms | Fast |
| PBKDF2 Derivation | ~100ms | One-time |
| AES Encryption | <1ms | Per message |
| AES Decryption | <1ms | Per message |

**Overhead:** 28 bytes per message (nonce + tag)

---

## Documentation

- **Full Security Details:** `SECURITY.md`
- **Complete Integration:** `INTEGRATION.md`
- **Verification Results:** `PRODUCTION_READY_VERIFICATION.md`

---

## Example: Complete Desktop Implementation

```dart
class RemoteControlService {
  late final TokenManager _tokenManager;
  late final SecureDiscovery _discovery;
  late final SecureSignalingServer _signaling;

  Future<void> initialize() async {
    final database = PairingDatabase();
    _tokenManager = TokenManager(database);
    _discovery = SecureDiscovery(_tokenManager, 'my-server-id');
    _signaling = SecureSignalingServer(_tokenManager);

    await _discovery.startServer(
      signalingPort: 45678,
      mode: DiscoveryMode.pairedOnly,
    );
    await _signaling.start();

    // Listen for new connections
    _signaling.onClientConnected.listen((deviceId) {
      print('Device connected: $deviceId');
    });
  }

  Future<String> startPairing() async {
    _discovery.setMode(DiscoveryMode.pairing, signalingPort: 45678);
    final code = await _tokenManager.startPairing();

    // Auto-disable after 5 minutes
    Timer(Duration(minutes: 5), () {
      _discovery.setMode(DiscoveryMode.pairedOnly, signalingPort: 45678);
    });

    return code;
  }

  Future<void> dispose() async {
    await _discovery.stopServer();
    await _signaling.stop();
  }
}
```

---

## Example: Complete Mobile Implementation

```dart
class MobileRemoteClient {
  final String deviceId = Uuid().v4();
  late ChannelEncryption _encryption;

  Future<bool> pairAndConnect(String host, String code) async {
    // 1. Pair
    final response = await http.post(
      Uri.parse('http://$host:8080/pair'),
      body: jsonEncode({
        'pairingCode': code,
        'deviceId': deviceId,
        'deviceName': 'My Phone',
      }),
    );

    if (response.statusCode != 200) return false;

    final sessionToken = jsonDecode(response.body)['sessionToken'];
    await _saveToken(host, sessionToken);

    // 2. Connect
    _encryption = ChannelEncryption.fromToken(sessionToken);
    final socket = await Socket.connect(host, 45678);

    // 3. Authenticate
    final authMsg = SignalingMessage(
      type: SignalingMessageType.authRequest,
      payload: {
        'deviceId': deviceId,
        'deviceName': 'My Phone',
        'sessionToken': sessionToken,
      },
    );
    socket.add(utf8.encode(jsonEncode(authMsg.toJson())));

    // 4. Listen for messages
    socket.listen((data) {
      final msg = _encryption.decryptJson(base64Encode(data));
      _handleMessage(msg);
    });

    return true;
  }

  void sendCommand(Socket socket, Map<String, dynamic> command) {
    final encrypted = _encryption.encryptJson(command);
    socket.add(base64Decode(encrypted));
  }
}
```

---

## Need Help?

1. Check documentation in package
2. Review examples above
3. Test with provided unit tests
4. Open issue with reproduction steps

---

**Quick Start Complete! You're ready to integrate secure WebRTC.**

---

*Nightshade 2.0 - Secure Remote Control*
