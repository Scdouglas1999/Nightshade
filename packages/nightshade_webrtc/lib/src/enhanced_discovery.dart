import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nsd/nsd.dart';

import 'discovery.dart';
import 'server_compatibility.dart';

/// SharedPreferences keys for server persistence
class _DiscoveryPrefs {
  static const lastServerHost = 'nightshade_last_server_host';
  static const lastServerPort = 'nightshade_last_server_port';
  static const lastServerSignalingPort =
      'nightshade_last_server_signaling_port';
  static const lastServerName = 'nightshade_last_server_name';
  static const lastServerVersion = 'nightshade_last_server_version';
  static const lastServerMode = 'nightshade_last_server_mode';
  static const lastServerAuthRequired = 'nightshade_last_server_auth_required';
  static const lastServerAuthMode = 'nightshade_last_server_auth_mode';
  static const lastServerPairingSupported =
      'nightshade_last_server_pairing_supported';
  static const lastServerAuthToken = 'nightshade_last_server_auth_token';
}

/// QR code connection data format
class QrConnectionData {
  final String host;
  final int webPort;
  final int signalingPort;
  final String? serverName;
  final String? version;
  final String mode;
  final bool authRequired;
  final String authenticationMode;
  final bool pairingSupported;
  final String? authToken;

  QrConnectionData({
    required this.host,
    required this.webPort,
    required this.signalingPort,
    this.serverName,
    this.version,
    this.mode = 'desktop',
    this.authRequired = false,
    this.authenticationMode = 'none',
    this.pairingSupported = false,
    this.authToken,
  });

  factory QrConnectionData.fromJson(Map<String, dynamic> json) {
    return QrConnectionData(
      host: json['host'] as String,
      webPort: json['webPort'] as int,
      signalingPort: json['signalingPort'] as int? ?? 45678,
      serverName: json['name'] as String?,
      version: json['version'] as String?,
      mode: json['mode'] as String? ?? 'desktop',
      authRequired: json['authRequired'] as bool? ?? false,
      authenticationMode: json['authenticationMode'] as String? ?? 'none',
      pairingSupported: json['pairingSupported'] as bool? ?? false,
      authToken: json['authToken'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'host': host,
        'webPort': webPort,
        'signalingPort': signalingPort,
        if (serverName != null) 'name': serverName,
        if (version != null) 'version': version,
        'mode': mode,
        'authRequired': authRequired,
        'authenticationMode': authenticationMode,
        'pairingSupported': pairingSupported,
        if (authToken != null && authToken!.isNotEmpty) 'authToken': authToken,
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
        version: version ?? '2.0.0',
        mode: mode,
        authRequired: authRequired,
        authenticationMode: authenticationMode,
        pairingSupported: pairingSupported,
        authToken: authToken,
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
    await prefs.setString(_DiscoveryPrefs.lastServerMode, server.mode);
    await prefs.setBool(
        _DiscoveryPrefs.lastServerAuthRequired, server.authRequired);
    await prefs.setString(
        _DiscoveryPrefs.lastServerAuthMode, server.authenticationMode);
    await prefs.setBool(
        _DiscoveryPrefs.lastServerPairingSupported, server.pairingSupported);
    if (server.authToken != null && server.authToken!.isNotEmpty) {
      await prefs.setString(
          _DiscoveryPrefs.lastServerAuthToken, server.authToken!);
    } else {
      await prefs.remove(_DiscoveryPrefs.lastServerAuthToken);
    }
    developer.log('Saved server: ${server.name} at ${server.host}',
        name: 'EnhancedDiscovery');
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
      mode: prefs.getString(_DiscoveryPrefs.lastServerMode) ?? 'desktop',
      authRequired:
          prefs.getBool(_DiscoveryPrefs.lastServerAuthRequired) ?? false,
      authenticationMode:
          prefs.getString(_DiscoveryPrefs.lastServerAuthMode) ?? 'none',
      pairingSupported:
          prefs.getBool(_DiscoveryPrefs.lastServerPairingSupported) ?? false,
      authToken: prefs.getString(_DiscoveryPrefs.lastServerAuthToken),
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
    await prefs.remove(_DiscoveryPrefs.lastServerMode);
    await prefs.remove(_DiscoveryPrefs.lastServerAuthRequired);
    await prefs.remove(_DiscoveryPrefs.lastServerAuthMode);
    await prefs.remove(_DiscoveryPrefs.lastServerPairingSupported);
    await prefs.remove(_DiscoveryPrefs.lastServerAuthToken);
    developer.log('Cleared saved server', name: 'EnhancedDiscovery');
  }

  static Map<String, String> _authHeaders(String? authToken) {
    final headers = {
      NightshadeServerCompatibility.apiVersionHeader:
          NightshadeServerCompatibility.clientApiVersion.format(),
    };
    if (authToken == null || authToken.isEmpty) {
      return headers;
    }
    return {
      ...headers,
      'Authorization': 'Bearer $authToken',
    };
  }

  static DiscoveredServer _mergeServerInfo(
    DiscoveredServer seed,
    Map<String, dynamic> info,
  ) {
    return seed.copyWith(
      name: info['name'] as String? ?? seed.name,
      version: info['version'] as String? ?? seed.version,
      mode: info['mode'] as String? ?? seed.mode,
      authRequired: info['authRequired'] as bool? ?? seed.authRequired,
      authenticationMode:
          info['authenticationMode'] as String? ?? seed.authenticationMode,
      pairingSupported:
          info['pairingSupported'] as bool? ?? seed.pairingSupported,
    );
  }

  static Future<DiscoveredServer?> fetchServerInfo(
    DiscoveredServer server, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse('http://${server.host}:${server.webPort}/api/info'),
            headers: _authHeaders(server.authToken),
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        return null;
      }

      final info = jsonDecode(response.body) as Map<String, dynamic>;
      return _mergeServerInfo(server, info);
    } catch (_) {
      return null;
    }
  }

  /// Test if a server is reachable via HTTP
  static Future<bool> testServerConnection(
    String host,
    int port, {
    String? authToken,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    try {
      final infoResponse = await http
          .get(
            Uri.parse('http://$host:$port/api/info'),
            headers: _authHeaders(authToken),
          )
          .timeout(timeout);

      if (infoResponse.statusCode != 200) {
        return false;
      }

      final info = jsonDecode(infoResponse.body) as Map<String, dynamic>;
      final compatibility = NightshadeServerCompatibility.check(
        info['version'] as String?,
      );
      if (!compatibility.isCompatible) {
        developer.log(
          'Incompatible Nightshade server: ${compatibility.message}',
          name: 'EnhancedDiscovery',
          level: 900,
        );
        return false;
      }

      final authRequired = info['authRequired'] as bool? ?? false;
      if (!authRequired) {
        return true;
      }

      if (authToken == null || authToken.isEmpty) {
        return false;
      }

      final statusResponse = await http
          .get(
            Uri.parse('http://$host:$port/api/status'),
            headers: _authHeaders(authToken),
          )
          .timeout(timeout);

      return statusResponse.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static bool _isCompatibleServer(DiscoveredServer server) {
    final compatibility = NightshadeServerCompatibility.check(server.version);
    if (!compatibility.isCompatible) {
      developer.log(
        'Skipping incompatible Nightshade server ${server.host}:${server.webPort}: ${compatibility.message}',
        name: 'EnhancedDiscovery',
        level: 900,
      );
      return false;
    }
    return true;
  }

  static Future<DiscoveredServer?> _firstCompatibleServer(
    List<DiscoveredServer> servers,
  ) async {
    for (final server in servers) {
      final enriched = await fetchServerInfo(server) ?? server;
      if (_isCompatibleServer(enriched)) {
        return enriched;
      }
    }
    return null;
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

    developer.log('Testing saved server: ${server.host}:${server.webPort}',
        name: 'EnhancedDiscovery');
    final isReachable = await testServerConnection(
      server.host,
      server.webPort,
      authToken: server.authToken,
      timeout: timeout,
    );

    if (isReachable) {
      developer.log('Saved server is reachable', name: 'EnhancedDiscovery');
      return await fetchServerInfo(server, timeout: timeout) ?? server;
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
              if (resolvedService.txt != null &&
                  resolvedService.txt!.isNotEmpty) {
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
                      signalingPort = int.tryParse(value?.toString() ?? '') ??
                          signalingPort;
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
              if (!servers.any((s) =>
                  s.host == server.host && s.webPort == server.webPort)) {
                final enriched = await fetchServerInfo(server) ?? server;
                servers.add(enriched);
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
      return _firstCompatibleServer(mdnsServers);
    }

    // 3. Fall back to UDP broadcast (3s timeout)
    onStatus?.call('Searching via network broadcast...');
    final udpServers = await discoverViaUdp(
      timeout: const Duration(seconds: 3),
      onStatus: onStatus,
    );
    if (udpServers.isNotEmpty) {
      developer.log('Found server via UDP broadcast',
          name: 'EnhancedDiscovery');
      return _firstCompatibleServer(udpServers);
    }

    // 4. No server found
    developer.log('No server found via any method',
        name: 'EnhancedDiscovery', level: 900);
    onStatus?.call('No server found');
    return null;
  }

  /// Generate QR code data string for a server
  static String generateQrData({
    required String host,
    required int webPort,
    int signalingPort = 45678,
    String? serverName,
    String? version,
    String mode = 'desktop',
    bool authRequired = false,
    String authenticationMode = 'none',
    bool pairingSupported = false,
    String? authToken,
  }) {
    final data = QrConnectionData(
      host: host,
      webPort: webPort,
      signalingPort: signalingPort,
      serverName: serverName,
      version: version,
      mode: mode,
      authRequired: authRequired,
      authenticationMode: authenticationMode,
      pairingSupported: pairingSupported,
      authToken: authToken,
    );
    return data.toQrString();
  }
}
