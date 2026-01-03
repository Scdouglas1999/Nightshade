import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nsd/nsd.dart';

import 'discovery.dart';

/// SharedPreferences keys for server persistence
class _DiscoveryPrefs {
  static const lastServerHost = 'nightshade_last_server_host';
  static const lastServerPort = 'nightshade_last_server_port';
  static const lastServerSignalingPort = 'nightshade_last_server_signaling_port';
  static const lastServerName = 'nightshade_last_server_name';
  static const lastServerVersion = 'nightshade_last_server_version';
}

/// QR code connection data format
class QrConnectionData {
  final String host;
  final int webPort;
  final int signalingPort;
  final String? serverName;

  QrConnectionData({
    required this.host,
    required this.webPort,
    required this.signalingPort,
    this.serverName,
  });

  factory QrConnectionData.fromJson(Map<String, dynamic> json) {
    return QrConnectionData(
      host: json['host'] as String,
      webPort: json['webPort'] as int,
      signalingPort: json['signalingPort'] as int? ?? 45678,
      serverName: json['name'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'host': host,
        'webPort': webPort,
        'signalingPort': signalingPort,
        if (serverName != null) 'name': serverName,
      };

  String toQrString() => jsonEncode(toJson());

  static QrConnectionData? fromQrString(String data) {
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      return QrConnectionData.fromJson(json);
    } catch (e) {
      return null;
    }
  }

  DiscoveredServer toDiscoveredServer() => DiscoveredServer(
        host: host,
        webPort: webPort,
        signalingPort: signalingPort,
        name: serverName ?? 'Nightshade',
        version: '2.0.0',
      );
}

/// Discovery status callback type
typedef DiscoveryStatusCallback = void Function(String status);

/// Enhanced discovery service with multiple fallback methods
class EnhancedNightshadeDiscovery {
  /// Save successful connection for future reconnects
  static Future<void> saveLastServer(DiscoveredServer server) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_DiscoveryPrefs.lastServerHost, server.host);
    await prefs.setInt(_DiscoveryPrefs.lastServerPort, server.webPort);
    await prefs.setInt(
        _DiscoveryPrefs.lastServerSignalingPort, server.signalingPort);
    await prefs.setString(_DiscoveryPrefs.lastServerName, server.name);
    await prefs.setString(_DiscoveryPrefs.lastServerVersion, server.version);
    print('[EnhancedDiscovery] Saved server: ${server.name} at ${server.host}');
  }

  /// Load last server from preferences
  static Future<DiscoveredServer?> loadLastServer() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString(_DiscoveryPrefs.lastServerHost);
    final port = prefs.getInt(_DiscoveryPrefs.lastServerPort);

    if (host == null || port == null) {
      return null;
    }

    return DiscoveredServer(
      host: host,
      webPort: port,
      signalingPort:
          prefs.getInt(_DiscoveryPrefs.lastServerSignalingPort) ?? 45678,
      name: prefs.getString(_DiscoveryPrefs.lastServerName) ?? 'Nightshade',
      version: prefs.getString(_DiscoveryPrefs.lastServerVersion) ?? '2.0.0',
    );
  }

  /// Clear saved server
  static Future<void> clearLastServer() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_DiscoveryPrefs.lastServerHost);
    await prefs.remove(_DiscoveryPrefs.lastServerPort);
    await prefs.remove(_DiscoveryPrefs.lastServerSignalingPort);
    await prefs.remove(_DiscoveryPrefs.lastServerName);
    await prefs.remove(_DiscoveryPrefs.lastServerVersion);
    print('[EnhancedDiscovery] Cleared saved server');
  }

  /// Test if a server is reachable via HTTP
  static Future<bool> testServerConnection(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    try {
      final response = await http
          .get(Uri.parse('http://$host:$port/api/info'))
          .timeout(timeout);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Try to reconnect to last saved server
  static Future<DiscoveredServer?> tryLastServer({
    Duration timeout = const Duration(seconds: 2),
    DiscoveryStatusCallback? onStatus,
  }) async {
    onStatus?.call('Checking last server...');
    final server = await loadLastServer();
    if (server == null) {
      print('[EnhancedDiscovery] No saved server found');
      return null;
    }

    print(
        '[EnhancedDiscovery] Testing saved server: ${server.host}:${server.webPort}');
    final isReachable =
        await testServerConnection(server.host, server.webPort, timeout: timeout);

    if (isReachable) {
      print('[EnhancedDiscovery] Saved server is reachable');
      return server;
    }

    print('[EnhancedDiscovery] Saved server not reachable');
    return null;
  }

  /// Discover via mDNS/Bonjour (platform-dependent)
  /// Uses the nsd package for cross-platform mDNS service discovery
  static Future<List<DiscoveredServer>> discoverViaMdns({
    Duration timeout = const Duration(seconds: 10),
    DiscoveryStatusCallback? onStatus,
  }) async {
    onStatus?.call('Searching via Bonjour...');
    print('[EnhancedDiscovery] mDNS discovery starting...');

    final List<DiscoveredServer> servers = [];
    // StreamSubscription<Service>? subscription;

    try {
      final discovery = await startDiscovery('_nightshade._tcp');

      // Collect discovered services
      final completer = Completer<List<DiscoveredServer>>();
      Timer? timeoutTimer;

      discovery.addServiceListener((service, status) async {
        if (status == ServiceStatus.found) {
          print('[EnhancedDiscovery] Found mDNS service: ${service.name}');

          try {
            // Resolve the service to get host and port
            final resolvedService = await resolve(service);

            if (resolvedService.host != null && resolvedService.port != null) {
              final host = resolvedService.host!;
              final port = resolvedService.port!;

              print('[EnhancedDiscovery] Resolved service: $host:$port');

              // Parse service name and TXT records for metadata
              String serverName = resolvedService.name ?? 'Nightshade';
              String version = '2.0.0';
              int signalingPort = 45678;

              // Parse TXT records if available
              if (resolvedService.txt != null && resolvedService.txt!.isNotEmpty) {
                final txtRecords = resolvedService.txt!;

                // TXT records are typically in key=value format
                for (var record in txtRecords.entries) {
                  final key = record.key;
                  final value = record.value;

                  switch (key) {
                    case 'version':
                      version = value?.toString() ?? version;
                      break;
                    case 'name':
                      serverName = value?.toString() ?? serverName;
                      break;
                    case 'signaling_port':
                      signalingPort = int.tryParse(value?.toString() ?? '') ?? signalingPort;
                      break;
                  }
                }
              }

              final server = DiscoveredServer(
                host: host,
                webPort: port,
                signalingPort: signalingPort,
                name: serverName,
                version: version,
              );

              // Avoid duplicates
              if (!servers.any((s) => s.host == server.host && s.webPort == server.webPort)) {
                servers.add(server);
                print('[EnhancedDiscovery] Added server: $serverName at $host:$port');
              }
            }
          } catch (e) {
            print('[EnhancedDiscovery] Failed to resolve service: $e');
          }
        }
      });

      // Set timeout for discovery
      timeoutTimer = Timer(timeout, () {
        if (!completer.isCompleted) {
          print('[EnhancedDiscovery] mDNS discovery timeout reached');
          completer.complete(servers);
        }
      });

      // Wait for timeout
      await completer.future;

      // Clean up
      timeoutTimer.cancel();
      // await subscription?.cancel();
      await stopDiscovery(discovery);

      print('[EnhancedDiscovery] mDNS discovery complete. Found ${servers.length} server(s)');
      return servers;

    } catch (e) {
      print('[EnhancedDiscovery] mDNS discovery error: $e');

      // Clean up on error
      // await subscription?.cancel();

      return servers;
    }
  }

  /// Discover via UDP broadcast (existing method)
  static Future<List<DiscoveredServer>> discoverViaUdp({
    Duration timeout = const Duration(seconds: 3),
    DiscoveryStatusCallback? onStatus,
  }) async {
    onStatus?.call('Searching via network broadcast...');
    return NightshadeDiscovery.discoverServers(timeout: timeout);
  }

  /// Parse QR code data into connection info
  static DiscoveredServer? parseQrCode(String qrData) {
    final data = QrConnectionData.fromQrString(qrData);
    return data?.toDiscoveredServer();
  }

  /// Full discovery flow with cascading fallbacks
  /// Order: Last server (2s) → mDNS (3s) → UDP broadcast (3s) → null
  static Future<DiscoveredServer?> discoverWithFallback({
    DiscoveryStatusCallback? onStatus,
  }) async {
    print('[EnhancedDiscovery] Starting cascading discovery...');

    // 1. Try last saved server (2s timeout)
    onStatus?.call('Reconnecting to last server...');
    final lastServer = await tryLastServer(
      timeout: const Duration(seconds: 2),
      onStatus: onStatus,
    );
    if (lastServer != null) {
      print('[EnhancedDiscovery] Connected via saved server');
      return lastServer;
    }

    // 2. Try mDNS discovery (3s timeout)
    onStatus?.call('Searching via Bonjour...');
    final mdnsServers = await discoverViaMdns(
      timeout: const Duration(seconds: 3),
      onStatus: onStatus,
    );
    if (mdnsServers.isNotEmpty) {
      print('[EnhancedDiscovery] Found server via mDNS');
      return mdnsServers.first;
    }

    // 3. Fall back to UDP broadcast (3s timeout)
    onStatus?.call('Searching via network broadcast...');
    final udpServers = await discoverViaUdp(
      timeout: const Duration(seconds: 3),
      onStatus: onStatus,
    );
    if (udpServers.isNotEmpty) {
      print('[EnhancedDiscovery] Found server via UDP broadcast');
      return udpServers.first;
    }

    // 4. No server found
    print('[EnhancedDiscovery] No server found via any method');
    onStatus?.call('No server found');
    return null;
  }

  /// Generate QR code data string for a server
  static String generateQrData({
    required String host,
    required int webPort,
    int signalingPort = 45678,
    String? serverName,
  }) {
    final data = QrConnectionData(
      host: host,
      webPort: webPort,
      signalingPort: signalingPort,
      serverName: serverName,
    );
    return data.toQrString();
  }
}
