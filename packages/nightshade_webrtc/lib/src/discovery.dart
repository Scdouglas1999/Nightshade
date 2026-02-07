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

  DiscoveredServer({
    required this.host,
    required this.webPort,
    required this.signalingPort,
    required this.name,
    required this.version,
  });

  String get webUrl => 'http://$host:$webPort';
  String get signalingUrl => 'http://$host:$signalingPort';

  @override
  String toString() => '$name ($host:$webPort)';
}

/// Automatic discovery service for Nightshade instances on local network
/// Uses UDP broadcast for zero-configuration discovery
class NightshadeDiscovery {
  static const int _discoveryPort = 45679;
  static const String _discoveryMessage = 'NIGHTSHADE_DISCOVERY';
  static const String _responsePrefix = 'NIGHTSHADE_RESPONSE:';


  /// Start broadcasting this server's presence (desktop/server side)
  static Future<RawDatagramSocket> startBroadcasting({
    required int webPort,
    required int signalingPort,
    String name = 'Nightshade',
    String version = '2.0.0',
  }) async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
      reuseAddress: true,
    );

    socket.broadcastEnabled = true;

    // Broadcast server info periodically
    Timer.periodic(const Duration(seconds: 2), (timer) {
      final info = {
        'name': name,
        'version': version,
        'webPort': webPort,
        'signalingPort': signalingPort,
      };
      final message = '$_responsePrefix${jsonEncode(info)}';
      final data = utf8.encode(message);

      // Broadcast to all interfaces
      // Works on Windows, Linux, and macOS
      try {
        socket.send(data, InternetAddress('255.255.255.255'), _discoveryPort);
      } catch (e) {
        // Ignore errors (network might not be ready, or firewall blocking)
        // On Windows, firewall may block UDP broadcasts initially
      }
    });

    return socket;
  }

  /// Discover Nightshade servers on the local network (mobile/client side)
  static Future<List<DiscoveredServer>> discoverServers({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final servers = <DiscoveredServer>[];
    final seen = <String>{};

    try {
      developer.log('Creating UDP socket for discovery...', name: 'NightshadeDiscovery');
      // Create socket for receiving responses
      // Must bind to the specific discovery port to receive broadcasts sent to that port
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _discoveryPort,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;
      developer.log('Socket bound to port $_discoveryPort, listening for broadcasts...', name: 'NightshadeDiscovery');

      socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram != null) {
            try {
              final message = utf8.decode(datagram.data);
              developer.log('Received UDP packet from ${datagram.address.address}', name: 'NightshadeDiscovery');
              if (message.startsWith(_responsePrefix)) {
                final jsonStr = message.substring(_responsePrefix.length);
                final info = jsonDecode(jsonStr) as Map<String, dynamic>;

                final host = datagram.address.address;
                final key = '${host}:${info['webPort']}';

                if (!seen.contains(key)) {
                  seen.add(key);
                  final server = DiscoveredServer(
                    host: host,
                    webPort: info['webPort'] as int,
                    signalingPort: info['signalingPort'] as int,
                    name: info['name'] as String? ?? 'Nightshade',
                    version: info['version'] as String? ?? '2.0.0',
                  );
                  servers.add(server);
                  developer.log('Found server: ${server.name} at $host', name: 'NightshadeDiscovery', level: 800);
                }
              }
            } catch (e) {
              developer.log('Error parsing packet: $e', name: 'NightshadeDiscovery', level: 1000);
            }
          }
        }
      });

      // Send discovery broadcast
      developer.log('Sending discovery broadcast to 255.255.255.255:$_discoveryPort', name: 'NightshadeDiscovery');
      final discoveryData = utf8.encode(_discoveryMessage);
      socket.send(discoveryData, InternetAddress('255.255.255.255'), _discoveryPort);

      // Wait for responses
      await Future.delayed(timeout);
      developer.log('Discovery timeout reached, found ${servers.length} servers', name: 'NightshadeDiscovery');
      socket.close();

      return servers;
    } catch (e) {
      developer.log('Discovery error: $e', name: 'NightshadeDiscovery', level: 1000);
      return servers;
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

