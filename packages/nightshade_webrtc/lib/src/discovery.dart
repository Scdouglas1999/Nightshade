import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:convert';

/// Discovered Nightshade server information
class DiscoveredServer {
  final String host;
  final int webPort;
  final int signalingPort;
  final String name;
  final String version;
  final String mode;
  final bool authRequired;
  final String authenticationMode;
  final bool pairingSupported;
  final String? authToken;

  DiscoveredServer({
    required this.host,
    required this.webPort,
    required this.signalingPort,
    required this.name,
    required this.version,
    this.mode = 'desktop',
    this.authRequired = false,
    this.authenticationMode = 'none',
    this.pairingSupported = false,
    this.authToken,
  });

  String get webUrl => 'http://$host:$webPort';
  String get signalingUrl => 'http://$host:$signalingPort';

  DiscoveredServer copyWith({
    String? host,
    int? webPort,
    int? signalingPort,
    String? name,
    String? version,
    String? mode,
    bool? authRequired,
    String? authenticationMode,
    bool? pairingSupported,
    String? authToken,
  }) {
    return DiscoveredServer(
      host: host ?? this.host,
      webPort: webPort ?? this.webPort,
      signalingPort: signalingPort ?? this.signalingPort,
      name: name ?? this.name,
      version: version ?? this.version,
      mode: mode ?? this.mode,
      authRequired: authRequired ?? this.authRequired,
      authenticationMode: authenticationMode ?? this.authenticationMode,
      pairingSupported: pairingSupported ?? this.pairingSupported,
      authToken: authToken ?? this.authToken,
    );
  }

  @override
  String toString() => '$name ($host:$webPort)';
}

/// Handle returned from [NightshadeDiscovery.startBroadcasting] so callers
/// can terminate the announcement loop without leaking the periodic timer.
///
/// Audit §3.11: previous implementation called `Timer.periodic(2 s)` with no
/// reference and no cancellation, leaking one timer per call.
class DiscoveryBroadcaster {
  final RawDatagramSocket socket;
  final Timer _timer;
  bool _stopped = false;

  DiscoveryBroadcaster._(this.socket, this._timer);

  /// Cancel the periodic broadcast and close the socket. Idempotent.
  void stop() {
    if (_stopped) return;
    _stopped = true;
    _timer.cancel();
    try {
      socket.close();
    } catch (_) {
      // Socket may already be closed by an earlier teardown — best-effort.
    }
  }
}

/// Automatic discovery service for Nightshade instances on local network.
/// Uses UDP broadcast for zero-configuration discovery.
///
/// Wire format: every datagram is a JSON object plus the UTF-8 prefix
/// `[_responsePrefix]` (server announcements) or `[_requestPrefix]` (client
/// probes). The previous implementation used `:`-delimited substrings which
/// collided with Nightshade device IDs (e.g. `native:vendor:idx`).
class NightshadeDiscovery {
  /// Server-side fixed port — desktop instances bind here so clients can
  /// target a known address.
  static const int _serverPort = 45679;
  // Marker bytes so we never mistake a stray UDP datagram for a Nightshade
  // packet. JSON alone is not sufficient — anything on the local LAN can
  // emit `{...}`.
  static const String _requestPrefix = 'NIGHTSHADE_DISCOVERY_V2:';
  static const String _responsePrefix = 'NIGHTSHADE_RESPONSE_V2:';
  static const String _protocolVersion = '2';

  /// Start broadcasting this server's presence (desktop/server side).
  ///
  /// Returned [DiscoveryBroadcaster] owns the socket + timer. Callers MUST
  /// call [DiscoveryBroadcaster.stop] on shutdown.
  static Future<DiscoveryBroadcaster> startBroadcasting({
    required int webPort,
    required int signalingPort,
    String name = 'Nightshade',
    String version = '2.0.0',
    Duration interval = const Duration(seconds: 2),
  }) async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      _serverPort,
      reuseAddress: true,
    );
    socket.broadcastEnabled = true;

    // Build the announcement once — payload is invariant across the run.
    final payload = {
      'protocol': _protocolVersion,
      'name': name,
      'version': version,
      'webPort': webPort,
      'signalingPort': signalingPort,
    };
    final messageBytes =
        utf8.encode('$_responsePrefix${jsonEncode(payload)}');

    void emit() {
      try {
        socket.send(
          messageBytes,
          InternetAddress('255.255.255.255'),
          _serverPort,
        );
      } catch (_) {
        // Network may not be ready, firewall may be blocking — keep trying
        // on the next tick rather than killing the loop.
      }
    }

    // Immediate emit so a client probing in this same tick gets a response,
    // then resume on the periodic schedule.
    emit();
    final timer = Timer.periodic(interval, (_) => emit());

    // Also respond directly to client probes so a client that joined after
    // our last broadcast tick doesn't have to wait for the next one.
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null) return;
      try {
        final raw = utf8.decode(datagram.data);
        if (!raw.startsWith(_requestPrefix)) return;
        socket.send(messageBytes, datagram.address, datagram.port);
      } catch (_) {
        // Malformed datagrams are ignored — they are noise on a shared LAN.
      }
    });

    return DiscoveryBroadcaster._(socket, timer);
  }

  /// Discover Nightshade servers on the local network (mobile/client side).
  ///
  /// Binds an ephemeral UDP port (port 0) so multiple clients on the same
  /// host don't fight for [_serverPort] — that port is reserved for the
  /// server. Sends a probe to the server port and listens on the ephemeral
  /// port for the responses targeted back at us.
  static Future<List<DiscoveredServer>> discoverServers({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final servers = <DiscoveredServer>[];
    final seen = <String>{};
    RawDatagramSocket? socket;

    try {
      developer.log('Creating UDP socket for discovery (ephemeral port)...',
          name: 'NightshadeDiscovery');
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;
      developer.log(
        'Client socket bound to ephemeral port ${socket.port}; '
        'targeting server port $_serverPort',
        name: 'NightshadeDiscovery',
      );

      socket.listen((RawSocketEvent event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket!.receive();
        if (datagram == null) return;
        try {
          final message = utf8.decode(datagram.data);
          if (!message.startsWith(_responsePrefix)) return;
          final jsonStr = message.substring(_responsePrefix.length);
          final info = jsonDecode(jsonStr);
          if (info is! Map<String, dynamic>) return;
          if (info['webPort'] is! int || info['signalingPort'] is! int) return;

          final host = datagram.address.address;
          final webPort = info['webPort'] as int;
          final key = '$host:$webPort';
          if (seen.contains(key)) return;
          seen.add(key);
          servers.add(DiscoveredServer(
            host: host,
            webPort: webPort,
            signalingPort: info['signalingPort'] as int,
            name: info['name'] is String
                ? info['name'] as String
                : 'Nightshade',
            version: info['version'] is String
                ? info['version'] as String
                : '2.0.0',
          ));
          developer.log('Found server: ${servers.last.name} at $host',
              name: 'NightshadeDiscovery', level: 800);
        } catch (e) {
          developer.log('Error parsing packet: $e',
              name: 'NightshadeDiscovery', level: 1000);
        }
      });

      // Structured probe — server-side validates the prefix; the JSON body
      // gives us a forward-compat hook for adding device-id / pairing fields
      // without breaking the protocol again.
      final probe = utf8.encode(
        '$_requestPrefix${jsonEncode({'protocol': _protocolVersion})}',
      );
      socket.send(probe, InternetAddress('255.255.255.255'), _serverPort);

      await Future.delayed(timeout);
      developer.log('Discovery timeout reached, found ${servers.length} servers',
          name: 'NightshadeDiscovery');
      return servers;
    } catch (e) {
      developer.log('Discovery error: $e',
          name: 'NightshadeDiscovery', level: 1000);
      return servers;
    } finally {
      socket?.close();
    }
  }

  /// Get the first discovered server (for auto-connect)
  static Future<DiscoveredServer?> discoverFirst({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final servers = await discoverServers(timeout: timeout);
    return servers.isNotEmpty ? servers.first : null;
  }
}

/// Discovered Nightshade instance for update pushing
class DiscoveredUpdateTarget {
  final String host;
  final int pushPort;
  final String name;
  final String version;
  final int buildNumber;
  final bool isReceiving;

  DiscoveredUpdateTarget({
    required this.host,
    required this.pushPort,
    required this.name,
    required this.version,
    required this.buildNumber,
    required this.isReceiving,
  });

  @override
  String toString() => '$name v$version ($host:$pushPort)';
}

/// Discovery service for finding Nightshade instances to push updates to
class UpdatePushDiscovery {
  static const int _discoveryPort = 45679;
  static const int _pushPort = 45680;
  static const String _updatePushMessage = 'NIGHTSHADE_UPDATE_PUSH';
  static const String _updateResponsePrefix = 'NIGHTSHADE_UPDATE_TARGET:';

  /// Discover Nightshade instances that can receive updates
  static Future<List<DiscoveredUpdateTarget>> discoverTargets({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final targets = <DiscoveredUpdateTarget>[];
    final seen = <String>{};

    try {
      developer.log('Creating UDP socket for discovery...', name: 'UpdatePushDiscovery');
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _discoveryPort,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;

      socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram != null) {
            try {
              final message = utf8.decode(datagram.data);
              if (message.startsWith(_updateResponsePrefix)) {
                final jsonStr = message.substring(_updateResponsePrefix.length);
                final info = jsonDecode(jsonStr) as Map<String, dynamic>;

                final host = datagram.address.address;
                final key = '$host:${info['pushPort']}';

                if (!seen.contains(key)) {
                  seen.add(key);
                  final target = DiscoveredUpdateTarget(
                    host: host,
                    pushPort: info['pushPort'] as int? ?? _pushPort,
                    name: info['name'] as String? ?? 'Nightshade',
                    version: info['version'] as String? ?? 'unknown',
                    buildNumber: info['buildNumber'] as int? ?? 0,
                    isReceiving: info['isReceiving'] as bool? ?? false,
                  );
                  targets.add(target);
                  developer.log('Found target: $target', name: 'UpdatePushDiscovery', level: 800);
                }
              }
            } catch (e) {
              developer.log('Error parsing packet: $e', name: 'UpdatePushDiscovery', level: 1000);
            }
          }
        }
      });

      // Send update push discovery broadcast
      developer.log('Sending discovery broadcast...', name: 'UpdatePushDiscovery');
      final discoveryData = utf8.encode(_updatePushMessage);
      socket.send(discoveryData, InternetAddress('255.255.255.255'), _discoveryPort);

      // Wait for responses
      await Future.delayed(timeout);
      developer.log('Discovery complete, found ${targets.length} targets', name: 'UpdatePushDiscovery');
      socket.close();

      return targets;
    } catch (e) {
      developer.log('Discovery error: $e', name: 'UpdatePushDiscovery', level: 1000);
      return targets;
    }
  }

  /// Start responding to update push discovery messages (desktop side)
  static Future<RawDatagramSocket> startResponding({
    required String name,
    required String version,
    required int buildNumber,
    required bool Function() isReceivingCallback,
  }) async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      _discoveryPort,
      reuseAddress: true,
    );
    socket.broadcastEnabled = true;

    socket.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        final datagram = socket.receive();
        if (datagram != null) {
          try {
            final message = utf8.decode(datagram.data);
            if (message == _updatePushMessage) {
              // Respond with our version info
              final info = {
                'name': name,
                'version': version,
                'buildNumber': buildNumber,
                'pushPort': _pushPort,
                'isReceiving': isReceivingCallback(),
              };
              final response = '$_updateResponsePrefix${jsonEncode(info)}';
              final data = utf8.encode(response);
              socket.send(data, datagram.address, datagram.port);
              developer.log('Responded to discovery from ${datagram.address.address}', name: 'UpdatePushDiscovery');
            }
          } catch (e) {
            developer.log('Error handling discovery: $e', name: 'UpdatePushDiscovery', level: 1000);
          }
        }
      }
    });

    developer.log('Listening for update push discovery on port $_discoveryPort', name: 'UpdatePushDiscovery', level: 800);
    return socket;
  }
}
