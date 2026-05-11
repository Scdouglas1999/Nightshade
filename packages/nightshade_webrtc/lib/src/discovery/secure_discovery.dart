import 'dart:async';
import 'dart:developer' as developer;
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

/// Secure discovery service that only responds to paired devices or pairing
/// requests.
///
/// Audit §3.11: previous wire format used `'$_discoveryMessage:$deviceId'`
/// and parsed it back with `message.split(':')[1]`. Nightshade device IDs
/// contain `:` themselves (`native:vendor:idx`; touptek is 4-part
/// `native:touptek:{brand}:{idx}`), so the split corrupted the parse and
/// `pairedOnly` mode silently rejected legitimate clients.
///
/// Wire format is now structured JSON, mirroring `discovery.dart`:
///   request : `[_requestPrefix]` + `{protocol, kind, deviceId?}`
///   response: `[_responsePrefix]` + `{protocol, host, signalingPort,
///                                     serverIdHash, isPairingMode}`
/// The marker prefixes remain so a random UDP datagram on the LAN can't be
/// mistaken for a Nightshade discovery packet just because it happens to be
/// JSON. Prefixes are bumped to `_V2` so we don't accept the broken
/// colon-delimited V1 format that this fix replaces.
class SecureDiscovery {
  static const int _discoveryPort = 45679;
  static const String _requestPrefix = 'NIGHTSHADE_SECURE_DISCOVERY_V2:';
  static const String _responsePrefix = 'NIGHTSHADE_SECURE_RESPONSE_V2:';
  static const String _protocolVersion = '2';
  // Request kinds — opaque strings so we can add new flows (e.g. an
  // ownership-transfer probe) without another wire-format break.
  static const String _kindDiscovery = 'discovery';
  static const String _kindPairing = 'pairing';

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
      developer.log('Server already running', name: 'SecureDiscovery', level: 900);
      return;
    }

    _mode = mode;

    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      _discoveryPort,
      reuseAddress: true,
    );

    _socket!.broadcastEnabled = true;

    developer.log('Secure discovery server started in ${mode.name} mode', name: 'SecureDiscovery', level: 800);

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
    final String message;
    try {
      message = utf8.decode(datagram.data);
    } on FormatException catch (e) {
      // Why: non-UTF8 datagram on a shared discovery port (a bystander
      // process, port-scanner, mDNS chatter, etc.). Without this guard the
      // throw escapes the socket listener into the zone error handler and
      // gets swallowed — exactly the silent failure CLAUDE.md warns against.
      // Log at warn level and drop the packet; we mirror the same handling
      // on the client in `_consumeResponse`.
      developer.log(
        'Non-UTF8 secure-discovery datagram dropped: $e',
        name: 'SecureDiscovery',
        level: 900,
      );
      return;
    }

    // Reject anything that isn't a Nightshade secure-discovery request before
    // we attempt JSON parsing. UDP on a shared LAN is noisy — we want to drop
    // unrelated traffic silently, but warn on anything that *claims* to be us
    // and then turns out malformed.
    if (!message.startsWith(_requestPrefix)) {
      return;
    }

    final jsonStr = message.substring(_requestPrefix.length);
    final Map<String, dynamic> req;
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map<String, dynamic>) {
        // Why: the spec mandates an object payload. Anything else is a
        // protocol violation from the caller, not a transport glitch.
        developer.log(
          'Malformed secure-discovery request (not a JSON object): $jsonStr',
          name: 'SecureDiscovery',
          level: 900,
        );
        return;
      }
      req = decoded;
    } on FormatException catch (e) {
      // Why: marker prefix matched but body is unparseable. Log loudly so
      // we notice a client / version-skew bug rather than dropping silently.
      developer.log(
        'Malformed secure-discovery request (invalid JSON): $e — body=$jsonStr',
        name: 'SecureDiscovery',
        level: 1000,
      );
      return;
    }

    final kind = req['kind'];
    if (kind is! String || (kind != _kindDiscovery && kind != _kindPairing)) {
      developer.log(
        'Malformed secure-discovery request (bad kind): $kind',
        name: 'SecureDiscovery',
        level: 900,
      );
      return;
    }
    final isPairingRequest = kind == _kindPairing;

    // deviceId is optional; presence is what gates pairedOnly mode. We
    // accept the *whole* string verbatim — Nightshade device IDs legitimately
    // contain `:` (e.g. `native:touptek:zwo:0`), which is exactly the case
    // the old split-on-`:` parser corrupted.
    final rawDeviceId = req['deviceId'];
    final String? deviceId = rawDeviceId is String && rawDeviceId.isNotEmpty
        ? rawDeviceId
        : null;

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
              .then((devices) =>
                  devices.where((d) => d.deviceId == deviceId).firstOrNull);
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
  }

  void _sendResponse(InternetAddress address, int signalingPort) {
    final response = {
      'protocol': _protocolVersion,
      'host': address.address,
      'signalingPort': signalingPort,
      'serverIdHash': _hashServerId(_serverId),
      'isPairingMode': _mode == DiscoveryMode.pairing,
    };

    final message = '$_responsePrefix${jsonEncode(response)}';
    final data = utf8.encode(message);

    // Why: socket.send can throw on transient network conditions (interface
    // disappearing during shutdown). Surface those rather than swallowing —
    // CLAUDE.md: "Silent fallbacks hide bugs for months."
    _socket!.send(data, address, _discoveryPort);
  }

  void _broadcastPresence(int signalingPort) {
    final response = {
      'protocol': _protocolVersion,
      'host': '0.0.0.0', // Will be replaced by receiver
      'signalingPort': signalingPort,
      'serverIdHash': _hashServerId(_serverId),
      'isPairingMode': true,
    };

    final message = '$_responsePrefix${jsonEncode(response)}';
    final data = utf8.encode(message);

    _socket!.send(data, InternetAddress('255.255.255.255'), _discoveryPort);
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

    developer.log('Mode changed to ${mode.name}', name: 'SecureDiscovery');
  }

  /// Stop the server
  Future<void> stopServer() async {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _socket?.close();
    _socket = null;
    developer.log('Server stopped', name: 'SecureDiscovery', level: 800);
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
      developer.log('Starting discovery...', name: 'SecureDiscovery');

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
            _consumeResponse(
              datagram: datagram,
              servers: servers,
              seen: seen,
              requirePairingMode: false,
            );
          }
        }
      });

      // Structured request payload (no more `discoveryMessage:deviceId` —
      // see §3.11). deviceId carries `:` legally and is now opaque.
      final payload = <String, dynamic>{
        'protocol': _protocolVersion,
        'kind': _kindDiscovery,
        if (deviceId != null && deviceId.isNotEmpty) 'deviceId': deviceId,
      };
      final data = utf8.encode('$_requestPrefix${jsonEncode(payload)}');
      socket.send(data, InternetAddress('255.255.255.255'), _discoveryPort);

      // Wait for responses
      await Future.delayed(timeout);
      socket.close();

      developer.log('Discovery complete, found ${servers.length} servers', name: 'SecureDiscovery');
      return servers;
    } catch (e) {
      developer.log('Discovery error: $e', name: 'SecureDiscovery', level: 1000);
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
      developer.log('Looking for servers in pairing mode...', name: 'SecureDiscovery');

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
            _consumeResponse(
              datagram: datagram,
              servers: servers,
              seen: seen,
              requirePairingMode: true,
            );
          }
        }
      });

      // Send structured pairing discovery request
      final payload = <String, dynamic>{
        'protocol': _protocolVersion,
        'kind': _kindPairing,
      };
      final data = utf8.encode('$_requestPrefix${jsonEncode(payload)}');
      socket.send(data, InternetAddress('255.255.255.255'), _discoveryPort);

      // Wait for responses
      await Future.delayed(timeout);
      socket.close();

      developer.log('Found ${servers.length} servers in pairing mode', name: 'SecureDiscovery');
      return servers;
    } catch (e) {
      developer.log('Discovery error: $e', name: 'SecureDiscovery', level: 1000);
      return servers;
    }
  }

  /// Parse a server response and append it to [servers] if valid and unseen.
  /// Pulled out of the two discoverXxx() methods so request/response shape is
  /// validated in exactly one place — both client flows had drifting copies.
  static void _consumeResponse({
    required Datagram datagram,
    required List<SecureDiscoveredServer> servers,
    required Set<String> seen,
    required bool requirePairingMode,
  }) {
    final String message;
    try {
      message = utf8.decode(datagram.data);
    } on FormatException catch (e) {
      // Why: non-UTF8 datagram on a discovery port — almost certainly a
      // bystander process on a shared port. Log at warn level (spec allows
      // recovery) and drop.
      developer.log(
        'Non-UTF8 secure-discovery response dropped: $e',
        name: 'SecureDiscovery',
        level: 900,
      );
      return;
    }

    if (!message.startsWith(_responsePrefix)) return;

    final jsonStr = message.substring(_responsePrefix.length);
    final Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map<String, dynamic>) {
        developer.log(
          'Malformed secure-discovery response (not a JSON object): $jsonStr',
          name: 'SecureDiscovery',
          level: 900,
        );
        return;
      }
      data = decoded;
    } on FormatException catch (e) {
      developer.log(
        'Malformed secure-discovery response (invalid JSON): $e — body=$jsonStr',
        name: 'SecureDiscovery',
        level: 1000,
      );
      return;
    }

    // Type-check every required field. We refuse to construct a server
    // record from a partial payload — a downstream caller relying on these
    // values would otherwise blow up much further from the source.
    final signalingPort = data['signalingPort'];
    final serverIdHash = data['serverIdHash'];
    final isPairingMode = data['isPairingMode'];
    if (signalingPort is! int ||
        serverIdHash is! String ||
        isPairingMode is! bool) {
      developer.log(
        'Malformed secure-discovery response (missing/typed fields): $data',
        name: 'SecureDiscovery',
        level: 900,
      );
      return;
    }

    if (requirePairingMode && !isPairingMode) return;

    final host = datagram.address.address;
    final key = '$host:$signalingPort';
    if (seen.contains(key)) return;
    seen.add(key);

    servers.add(SecureDiscoveredServer(
      host: host,
      signalingPort: signalingPort,
      serverIdHash: serverIdHash,
      isPairingMode: isPairingMode,
    ));
    developer.log(
      'Found ${requirePairingMode ? "pairing " : ""}server: $host',
      name: 'SecureDiscovery',
      level: 800,
    );
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
