import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nsd/nsd.dart';

import 'discovery.dart';
import 'server_compatibility.dart';

/// SharedPreferences keys for server persistence.
///
/// The auth-token key has been split: [lastServerAuthToken] is the legacy
/// plaintext SharedPreferences slot we read once on first launch and then
/// purge. The live token now lives in [_secureAuthTokenKey] inside
/// flutter_secure_storage (Keychain on iOS, EncryptedSharedPreferences on
/// Android, libsecret/DPAPI on desktop).
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
  // Legacy plaintext slot. Reads only — never written. Cleared after migration.
  static const lastServerAuthToken = 'nightshade_last_server_auth_token';
  // Set once after the legacy plaintext token has been read into secure
  // storage so we don't keep poking SharedPreferences on every load.
  static const authTokenMigrated = 'nightshade_auth_token_migrated_v1';
}

const String _secureAuthTokenKey = 'nightshade_last_server_auth_token';

const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
  // iOS: token survives reinstall but is bound to passcode/biometrics so a
  // jailbroken or backed-up device cannot exfiltrate it without unlock.
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
  // Android: EncryptedSharedPreferences with hardware-backed keys when
  // available.
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

/// One-shot migration: lift any plaintext token sitting in SharedPreferences
/// into secure storage and wipe the original. Idempotent — guarded by
/// [_DiscoveryPrefs.authTokenMigrated].
Future<void> _migrateAuthTokenIfNeeded(SharedPreferences prefs) async {
  if (prefs.getBool(_DiscoveryPrefs.authTokenMigrated) == true) return;
  final legacy = prefs.getString(_DiscoveryPrefs.lastServerAuthToken);
  if (legacy != null && legacy.isNotEmpty) {
    // Don't clobber an existing secure value — if both somehow exist, the
    // secure one wins (it was the result of an explicit save).
    final existing = await _secureStorage.read(key: _secureAuthTokenKey);
    if (existing == null || existing.isEmpty) {
      await _secureStorage.write(key: _secureAuthTokenKey, value: legacy);
    }
  }
  await prefs.remove(_DiscoveryPrefs.lastServerAuthToken);
  await prefs.setBool(_DiscoveryPrefs.authTokenMigrated, true);
  developer.log(
    'Migrated auth token from SharedPreferences to secure storage',
    name: 'EnhancedDiscovery',
  );
}

/// Service discriminator embedded in every Nightshade pairing QR.
/// Mobile clients reject any payload whose `service` field does not match this
/// constant — the QR scanner must refuse arbitrary JSON-shaped blobs.
const String kQrServiceMarker = 'nightshade';

/// Reasons a QR payload can be rejected. Surfaced to the UI so operators see
/// *why* the scan failed instead of a generic "invalid QR".
enum QrRejectionReason {
  notJson,
  missingService,
  wrongService,
  missingHost,
  invalidHost,
  hostNotLocal,
  missingPort,
  invalidPort,
  missingVersion,
  invalidVersion,
  missingFingerprint,
  invalidFingerprint,
}

class QrValidationException implements Exception {
  final QrRejectionReason reason;
  final String message;
  const QrValidationException(this.reason, this.message);

  @override
  String toString() => 'QrValidationException(${reason.name}): $message';
}

/// QR code connection data format.
///
/// `service`, `host`, `port`, `version`, and `fingerprint` are mandatory and
/// validated by [QrConnectionData.parseStrict]. The remaining fields are
/// optional metadata that survives round-tripping but is not part of the
/// trust-establishment contract.
class QrConnectionData {
  final String service;
  final String host;
  final int webPort;
  final int signalingPort;
  final String version;
  final String fingerprint;
  final String? serverName;
  final String mode;
  final bool authRequired;
  final String authenticationMode;
  final bool pairingSupported;
  final String? authToken;

  QrConnectionData({
    this.service = kQrServiceMarker,
    required this.host,
    required this.webPort,
    required this.version,
    required this.fingerprint,
    this.signalingPort = 45678,
    this.serverName,
    this.mode = 'desktop',
    this.authRequired = false,
    this.authenticationMode = 'none',
    this.pairingSupported = false,
    this.authToken,
  });

  /// Short hash for confirmation UI (first 16 chars of the fingerprint).
  String get shortFingerprint =>
      fingerprint.length <= 16 ? fingerprint : fingerprint.substring(0, 16);

  Map<String, dynamic> toJson() => {
        'service': service,
        'host': host,
        'port': webPort,
        'signalingPort': signalingPort,
        'version': version,
        'fingerprint': fingerprint,
        if (serverName != null) 'name': serverName,
        'mode': mode,
        'authRequired': authRequired,
        'authenticationMode': authenticationMode,
        'pairingSupported': pairingSupported,
        if (authToken != null && authToken!.isNotEmpty) 'authToken': authToken,
      };

  String toQrString() => jsonEncode(toJson());

  /// Strict parser. Throws [QrValidationException] on any schema violation —
  /// the audit calls out that lenient parsing was the bug. Callers are
  /// expected to surface the reason to the operator.
  static QrConnectionData parseStrict(String data) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(data);
    } catch (_) {
      throw const QrValidationException(
        QrRejectionReason.notJson,
        'QR payload is not valid JSON.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const QrValidationException(
        QrRejectionReason.notJson,
        'QR payload is not a JSON object.',
      );
    }

    final service = decoded['service'];
    if (service == null) {
      throw const QrValidationException(
        QrRejectionReason.missingService,
        'QR payload is missing the "service" discriminator.',
      );
    }
    if (service is! String || service != kQrServiceMarker) {
      throw const QrValidationException(
        QrRejectionReason.wrongService,
        'QR payload is not a Nightshade pairing code.',
      );
    }

    final host = decoded['host'];
    if (host == null) {
      throw const QrValidationException(
        QrRejectionReason.missingHost,
        'QR payload is missing "host".',
      );
    }
    if (host is! String || host.isEmpty) {
      throw const QrValidationException(
        QrRejectionReason.invalidHost,
        'QR payload "host" is not a non-empty string.',
      );
    }
    if (!isLocalNetworkHost(host)) {
      throw QrValidationException(
        QrRejectionReason.hostNotLocal,
        'QR payload "$host" is not on a local/private network.',
      );
    }

    final port = decoded['port'];
    if (port == null) {
      throw const QrValidationException(
        QrRejectionReason.missingPort,
        'QR payload is missing "port".',
      );
    }
    if (port is! int || port <= 0 || port > 65535) {
      throw const QrValidationException(
        QrRejectionReason.invalidPort,
        'QR payload "port" is not a valid TCP port.',
      );
    }

    final version = decoded['version'];
    if (version == null) {
      throw const QrValidationException(
        QrRejectionReason.missingVersion,
        'QR payload is missing "version".',
      );
    }
    if (version is! String || version.isEmpty) {
      throw const QrValidationException(
        QrRejectionReason.invalidVersion,
        'QR payload "version" is not a non-empty string.',
      );
    }

    final fingerprint = decoded['fingerprint'];
    if (fingerprint == null) {
      throw const QrValidationException(
        QrRejectionReason.missingFingerprint,
        'QR payload is missing "fingerprint".',
      );
    }
    if (fingerprint is! String || fingerprint.length < 8) {
      throw const QrValidationException(
        QrRejectionReason.invalidFingerprint,
        'QR payload "fingerprint" is not at least 8 characters.',
      );
    }

    final signalingPort = decoded['signalingPort'];
    final int parsedSignalingPort;
    if (signalingPort == null) {
      parsedSignalingPort = 45678;
    } else if (signalingPort is int &&
        signalingPort > 0 &&
        signalingPort <= 65535) {
      parsedSignalingPort = signalingPort;
    } else {
      throw const QrValidationException(
        QrRejectionReason.invalidPort,
        'QR payload "signalingPort" is not a valid TCP port.',
      );
    }

    return QrConnectionData(
      service: service,
      host: host,
      webPort: port,
      signalingPort: parsedSignalingPort,
      version: version,
      fingerprint: fingerprint,
      serverName: decoded['name'] is String ? decoded['name'] as String : null,
      mode: decoded['mode'] is String ? decoded['mode'] as String : 'desktop',
      authRequired: decoded['authRequired'] is bool
          ? decoded['authRequired'] as bool
          : false,
      authenticationMode: decoded['authenticationMode'] is String
          ? decoded['authenticationMode'] as String
          : 'none',
      pairingSupported: decoded['pairingSupported'] is bool
          ? decoded['pairingSupported'] as bool
          : false,
      authToken:
          decoded['authToken'] is String ? decoded['authToken'] as String : null,
    );
  }

  DiscoveredServer toDiscoveredServer() => DiscoveredServer(
        host: host,
        webPort: webPort,
        signalingPort: signalingPort,
        name: serverName ?? 'Nightshade',
        version: version,
        mode: mode,
        authRequired: authRequired,
        authenticationMode: authenticationMode,
        pairingSupported: pairingSupported,
        authToken: authToken,
      );
}

/// Returns `true` iff [host] is in an RFC1918 / link-local / loopback / IPv6
/// link-local range, or is an `.local` mDNS name. Public-Internet hosts in a
/// pairing QR almost certainly mean the QR was tampered with.
bool isLocalNetworkHost(String host) {
  if (host.isEmpty) return false;
  final lower = host.toLowerCase();

  // mDNS / Bonjour names. `localhost` covered by the IPv4 path below too.
  if (lower == 'localhost' || lower.endsWith('.local')) return true;

  // IPv6: strip optional brackets and zone-id suffix (e.g. `fe80::1%eth0`).
  var candidate = lower;
  if (candidate.startsWith('[') && candidate.endsWith(']')) {
    candidate = candidate.substring(1, candidate.length - 1);
  }
  final zoneIdx = candidate.indexOf('%');
  if (zoneIdx >= 0) {
    candidate = candidate.substring(0, zoneIdx);
  }

  final ipv4 = _parseIpv4(candidate);
  if (ipv4 != null) {
    final a = ipv4[0];
    final b = ipv4[1];
    // 10.0.0.0/8
    if (a == 10) return true;
    // 172.16.0.0/12
    if (a == 172 && b >= 16 && b <= 31) return true;
    // 192.168.0.0/16
    if (a == 192 && b == 168) return true;
    // 127.0.0.0/8 (loopback)
    if (a == 127) return true;
    // 169.254.0.0/16 (link-local)
    if (a == 169 && b == 254) return true;
    return false;
  }

  // IPv6 loopback `::1` and link-local `fe80::/10`. We don't fully parse
  // arbitrary IPv6 forms here — InternetAddress.tryParse is the cheap canon.
  final parsed = InternetAddress.tryParse(candidate);
  if (parsed != null && parsed.type == InternetAddressType.IPv6) {
    if (parsed.isLoopback) return true;
    final raw = parsed.rawAddress;
    if (raw.length >= 2) {
      // fe80::/10 → first byte 0xFE, top two bits of second byte 0b10xxxxxx.
      if (raw[0] == 0xFE && (raw[1] & 0xC0) == 0x80) return true;
    }
    return false;
  }

  return false;
}

List<int>? _parseIpv4(String value) {
  final parts = value.split('.');
  if (parts.length != 4) return null;
  final out = <int>[];
  for (final part in parts) {
    if (part.isEmpty) return null;
    final n = int.tryParse(part);
    if (n == null || n < 0 || n > 255) return null;
    out.add(n);
  }
  return out;
}

/// Discovery status callback type
typedef DiscoveryStatusCallback = void Function(String status);

/// Enhanced discovery service with multiple fallback methods
class EnhancedNightshadeDiscovery {
  /// Save successful connection for future reconnects.
  ///
  /// Host/port/version metadata stays in SharedPreferences — none of it is
  /// secret and reading it on the cold path doesn't need a Keychain unlock.
  /// The bearer token is written exclusively to secure storage.
  static Future<void> saveLastServer(DiscoveredServer server) async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateAuthTokenIfNeeded(prefs);
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
      await _secureStorage.write(
          key: _secureAuthTokenKey, value: server.authToken);
    } else {
      await _secureStorage.delete(key: _secureAuthTokenKey);
    }
    developer.log('Saved server: ${server.name} at ${server.host}',
        name: 'EnhancedDiscovery');
  }

  /// Load last server from preferences. Migrates the auth token out of
  /// plaintext SharedPreferences on first call.
  static Future<DiscoveredServer?> loadLastServer() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateAuthTokenIfNeeded(prefs);
    final host = prefs.getString(_DiscoveryPrefs.lastServerHost);
    final port = prefs.getInt(_DiscoveryPrefs.lastServerPort);

    if (host == null || port == null) {
      return null;
    }

    final authToken = await _secureStorage.read(key: _secureAuthTokenKey);

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
      authToken: (authToken != null && authToken.isNotEmpty) ? authToken : null,
    );
  }

  /// Clear saved server (and wipe the secure-storage token).
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
    // Legacy slot — should already be empty post-migration but flush anyway
    // in case the user wiped storage out from under us.
    await prefs.remove(_DiscoveryPrefs.lastServerAuthToken);
    await _secureStorage.delete(key: _secureAuthTokenKey);
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
    } catch (e, stackTrace) {
      // Why: best-effort enrichment of an already-discovered server. A failure
      // here (network blip, auth rejection, malformed JSON) means we display
      // the un-enriched server entry rather than hiding it — the discovery
      // list stays useful. Log so that a systemic mismatch (e.g. version
      // skew rejecting every /api/info) surfaces in the dev console.
      developer.log(
        'fetchServerInfo failed for ${server.host}:${server.webPort}: $e\n$stackTrace',
        name: 'EnhancedDiscovery',
        level: 900,
      );
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
    } catch (e, stackTrace) {
      // Why: reachability probe — any exception (connection refused, DNS
      // failure, timeout, TLS error) is by definition "not reachable" and
      // the caller treats `false` accordingly. Log so an operator chasing
      // "why doesn't my server show up" can see the actual cause.
      developer.log(
        'testServerConnection failed for $host:$port: $e\n$stackTrace',
        name: 'EnhancedDiscovery',
        level: 900,
      );
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
          } catch (e, stackTrace) {
            // Why: a single service-resolution failure during mDNS discovery
            // must not abort the whole sweep — another service in the same
            // broadcast may still resolve cleanly. Log at fine level so a
            // systemic Bonjour failure is visible in the dev console.
            developer.log(
              'mDNS service resolution failed; skipping: $e\n$stackTrace',
              name: 'EnhancedDiscovery',
              level: 500,
            );
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
        } catch (e, stackTrace) {
          // Why: cleanup in a finally block — the discovery sweep already
          // completed (or timed out); failing to close the mDNS handle is
          // non-fatal but should not propagate and mask the real outcome.
          // Log so a leaking handle pattern would be visible.
          developer.log(
            'stopDiscovery cleanup failed: $e\n$stackTrace',
            name: 'EnhancedDiscovery',
            level: 500,
          );
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

  /// Parse QR code data into connection info.
  ///
  /// Returns the validated [QrConnectionData] (NOT a [DiscoveredServer]) so
  /// callers can show a confirmation sheet with host + fingerprint *before*
  /// any network call. Throws [QrValidationException] on schema violation.
  static QrConnectionData parseQrCodeStrict(String qrData) =>
      QrConnectionData.parseStrict(qrData);

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

  /// Generate QR code data string for a server.
  ///
  /// `version` and `fingerprint` are mandatory — the mobile scanner refuses
  /// payloads without them (see §3.1 of the v2.5.0 audit).
  static String generateQrData({
    required String host,
    required int webPort,
    required String version,
    required String fingerprint,
    int signalingPort = 45678,
    String? serverName,
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
      version: version,
      fingerprint: fingerprint,
      serverName: serverName,
      mode: mode,
      authRequired: authRequired,
      authenticationMode: authenticationMode,
      pairingSupported: pairingSupported,
      authToken: authToken,
    );
    return data.toQrString();
  }
}
