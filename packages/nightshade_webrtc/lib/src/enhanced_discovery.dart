import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

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
    developer.log('Saved server: ${server.name} at ${server.host}', name: 'EnhancedDiscovery');
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
    developer.log('Cleared saved server', name: 'EnhancedDiscovery');
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
      developer.log('No saved server found', name: 'EnhancedDiscovery');
      return null;
    }

    developer.log('Testing saved server: ${server.host}:${server.webPort}', name: 'EnhancedDiscovery');
    final isReachable =
        await testServerConnection(server.host, server.webPort, timeout: timeout);

    if (isReachable) {
      developer.log('Saved server is reachable', name: 'EnhancedDiscovery');
      return server;
    }

    developer.log('Saved server not reachable', name: 'EnhancedDiscovery');
    return null;
  }

  /// Discover via mDNS/Bonjour (platform-dependent)
  /// Uses the nsd package for cross-platform mDNS service discovery
  static Future<List<DiscoveredServer>> discoverViaMdns({
    Duration timeout = const Duration(seconds: 10),
    DiscoveryStatusCallback? onStatus,
  }) async {
    onStatus?.call('Searching via Bonjour...');
    developer.log('mDNS discovery starting...', name: 'EnhancedDiscovery');

    final List<DiscoveredServer> servers = [];

    Discovery? discovery;
    Timer? timeoutTimer;

    try {
      discovery = await startDiscovery('_nightshade._tcp');

      // Collect discovered services
      final completer = Completer<List<DiscoveredServer>>();

      discovery.addServiceListener((service, status) async {
        if (status == ServiceStatus.found) {
          try {
            // Resolve the service to get host and port
            final resolvedService = await resolve(service);

            if (resolvedService.host != null && resolvedService.port != null) {
              final host = resolvedService.host!;
              final port = resolvedService.port!;

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
              }
            }
          } catch (_) {
            // Service resolution can fail for transient network reasons — skip this service
          }
        }
      });

      // Set timeout for discovery
      timeoutTimer = Timer(timeout, () {
        if (!completer.isCompleted) {
          completer.complete(servers);
        }
      });

      // Wait for timeout
      await completer.future;

      return servers;
    } catch (e) {
      // mDNS discovery can fail on platforms without Bonjour support
      return servers;
    } finally {
      timeoutTimer?.cancel();
      if (discovery != null) {
        try {
          await stopDiscovery(discovery);
        } catch (_) {
          // Best-effort cleanup
        }
      }
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
    developer.log('Starting cascading discovery...', name: 'EnhancedDiscovery');

    // 1. Try last saved server (2s timeout)
    onStatus?.call('Reconnecting to last server...');
    final lastServer = await tryLastServer(
      timeout: const Duration(seconds: 2),
      onStatus: onStatus,
    );
    if (lastServer != null) {
      developer.log('Connected via saved server', name: 'EnhancedDiscovery');
      return lastServer;
    }

    // 2. Try mDNS discovery (3s timeout)
    onStatus?.call('Searching via Bonjour...');
    final mdnsServers = await discoverViaMdns(
      timeout: const Duration(seconds: 3),
      onStatus: onStatus,
    );
    if (mdnsServers.isNotEmpty) {
      developer.log('Found server via mDNS', name: 'EnhancedDiscovery');
      return mdnsServers.first;
    }

    // 3. Fall back to UDP broadcast (3s timeout)
    onStatus?.call('Searching via network broadcast...');
    final udpServers = await discoverViaUdp(
      timeout: const Duration(seconds: 3),
      onStatus: onStatus,
    );
    if (udpServers.isNotEmpty) {
      developer.log('Found server via UDP broadcast', name: 'EnhancedDiscovery');
      return udpServers.first;
    }

    // 4. No server found
    developer.log('No server found via any method', name: 'EnhancedDiscovery', level: 900);
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
