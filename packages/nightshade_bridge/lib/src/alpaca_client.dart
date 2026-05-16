/// Alpaca Client - Direct Dart implementation for ASCOM Alpaca devices
///
/// Alpaca is a REST-based protocol for controlling astronomical equipment.
/// This allows cross-platform device connectivity without native code.
/// Reference: https://ascom-standards.org/api/
///
/// Features:
/// - Automatic retry with exponential backoff on network failures
/// - Circuit breaker pattern to prevent request floods
/// - Connection health tracking per device

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:http/http.dart' as http;
import 'utils/retry.dart';
import 'utils/circuit_breaker.dart';

// ============================================================================
// Alpaca Discovery
// ============================================================================

/// Alpaca discovery port (standard)
const int alpacaDiscoveryPort = 32227;

/// Alpaca discovery message
const String alpacaDiscoveryMessage = 'alpacadiscovery1';

/// Information about a discovered Alpaca server
class AlpacaServer {
  final String host;
  final int port;

  AlpacaServer({required this.host, required this.port});

  String get baseUrl => 'http://$host:$port';

  @override
  String toString() => 'AlpacaServer($host:$port)';
}

/// Information about an Alpaca device
class AlpacaDevice {
  final String deviceName;
  final String deviceType;
  final int deviceNumber;
  final String uniqueId;
  final AlpacaServer server;

  AlpacaDevice({
    required this.deviceName,
    required this.deviceType,
    required this.deviceNumber,
    required this.uniqueId,
    required this.server,
  });

  /// Generate a unique device ID
  String get id =>
      'alpaca:${server.host}:${server.port}/$deviceType/$deviceNumber';

  /// Get the API base URL for this device
  String get apiBaseUrl => '${server.baseUrl}/api/v1/$deviceType/$deviceNumber';

  @override
  String toString() =>
      'AlpacaDevice($deviceName, $deviceType #$deviceNumber at ${server.host})';
}

/// Discover Alpaca servers on the local network using UDP broadcast
Future<List<AlpacaServer>> discoverAlpacaServers({
  Duration timeout = const Duration(seconds: 3),
}) async {
  final servers = <AlpacaServer>[];

  try {
    // Create UDP socket for broadcast
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
      reuseAddress: true,
    );

    socket.broadcastEnabled = true;

    // Listen for responses
    socket.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        final datagram = socket.receive();
        if (datagram != null) {
          try {
            final response = utf8.decode(datagram.data);
            final json = jsonDecode(response) as Map<String, dynamic>;

            if (json.containsKey('AlpacaPort')) {
              final alpacaPort = json['AlpacaPort'] as int;
              final host = datagram.address.address;

              // Avoid duplicates
              if (!servers.any((s) => s.host == host && s.port == alpacaPort)) {
                servers.add(AlpacaServer(host: host, port: alpacaPort));
                developer.log(
                    '[Alpaca] Discovered server at $host:$alpacaPort',
                    name: 'AlpacaClient',
                    level: 800);
              }
            }
          } catch (e) {
            // Ignore malformed responses
          }
        }
      }
    });

    // Send discovery broadcast
    final message = utf8.encode(alpacaDiscoveryMessage);
    socket.send(
        message, InternetAddress('255.255.255.255'), alpacaDiscoveryPort);

    // Also try common localhost ports for ASCOM Remote
    _tryLocalPorts(servers);

    // Wait for timeout
    await Future<void>.delayed(timeout);
    socket.close();

    return servers;
  } catch (e) {
    developer.log('[Alpaca] Discovery error: $e',
        name: 'AlpacaClient', level: 900, error: e);
    // Try common localhost ports as fallback
    await _tryLocalPorts(servers);
    return servers;
  }
}

/// Try common localhost ports for ASCOM Remote Server
Future<void> _tryLocalPorts(List<AlpacaServer> servers) async {
  final commonPorts = [11111, 32323, 8080];

  for (final port in commonPorts) {
    try {
      final client = http.Client();
      final response = await client
          .get(Uri.parse('http://localhost:$port/management/apiversions'))
          .timeout(const Duration(milliseconds: 500));

      if (response.statusCode == 200) {
        if (!servers.any((s) => s.host == 'localhost' && s.port == port)) {
          servers.add(AlpacaServer(host: 'localhost', port: port));
          developer.log('[Alpaca] Found server at localhost:$port',
              name: 'AlpacaClient', level: 800);
        }
      }
      client.close();
    } catch (e) {
      // Port not responding
    }
  }
}

/// Get configured devices from an Alpaca server
Future<List<AlpacaDevice>> getAlpacaDevices(AlpacaServer server) async {
  final devices = <AlpacaDevice>[];

  try {
    final client = http.Client();
    final uri = Uri.parse('${server.baseUrl}/management/v1/configureddevices');
    final response = await client.get(uri).timeout(const Duration(seconds: 5));

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final value = json['Value'] as List<dynamic>?;

      if (value != null) {
        for (final deviceJson in value) {
          final device = deviceJson as Map<String, dynamic>;
          devices.add(AlpacaDevice(
            deviceName: device['DeviceName'] as String? ?? 'Unknown',
            deviceType:
                (device['DeviceType'] as String?)?.toLowerCase() ?? 'unknown',
            deviceNumber: device['DeviceNumber'] as int? ?? 0,
            uniqueId: device['UniqueID'] as String? ?? '',
            server: server,
          ));
        }
      }
    }

    client.close();
  } catch (e) {
    developer.log(
        '[Alpaca] Error getting devices from ${server.baseUrl}: $e',
        name: 'AlpacaClient',
        level: 900,
        error: e);
  }

  return devices;
}

/// Discover all Alpaca devices on the network
Future<List<AlpacaDevice>> discoverAllAlpacaDevices({
  Duration timeout = const Duration(seconds: 3),
}) async {
  final servers = await discoverAlpacaServers(timeout: timeout);
  final devices = <AlpacaDevice>[];

  for (final server in servers) {
    final serverDevices = await getAlpacaDevices(server);
    devices.addAll(serverDevices);
  }

  return devices;
}

// ============================================================================
// Alpaca Client for Device Communication
// ============================================================================

/// Client for communicating with an Alpaca device
class AlpacaClient {
  final AlpacaDevice device;
  final http.Client _httpClient;

  int _clientId = 1;
  int _transactionId = 0;

  // Connection resilience
  late final CircuitBreaker _circuitBreaker;
  static final CircuitBreakerRegistry _breakerRegistry =
      CircuitBreakerRegistry();

  AlpacaClient(this.device) : _httpClient = http.Client() {
    // Create or reuse circuit breaker for this device
    _circuitBreaker = _breakerRegistry.getOrCreate(
      device.id,
      config: const CircuitBreakerConfig(
        failureThreshold: 5,
        successThreshold: 2,
        resetTimeout: Duration(seconds: 30),
        operationTimeout: Duration(seconds: 30),
      ),
    );
  }

  /// Get circuit breaker state for health monitoring
  CircuitState get connectionHealth => _circuitBreaker.state;

  /// Get circuit breaker metrics
  Map<String, dynamic> getHealthMetrics() => _circuitBreaker.getMetrics();

  /// Make a GET request to the device with retry and circuit breaker
  Future<Map<String, dynamic>> get(String property) async {
    return _executeWithResilience(() async {
      final uri =
          Uri.parse('${device.apiBaseUrl}/$property').replace(queryParameters: {
        'ClientID': _clientId.toString(),
        'ClientTransactionID': (++_transactionId).toString(),
      });

      final response =
          await _httpClient.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw AlpacaException(
            'HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      if (json['ErrorNumber'] != 0) {
        throw AlpacaException(
            'Alpaca error ${json['ErrorNumber']}: ${json['ErrorMessage']}');
      }

      return json;
    });
  }

  /// Make a PUT request to the device with retry and circuit breaker
  Future<Map<String, dynamic>> put(String method,
      [Map<String, String>? params]) async {
    return _executeWithResilience(() async {
      final uri = Uri.parse('${device.apiBaseUrl}/$method');

      final body = {
        'ClientID': _clientId.toString(),
        'ClientTransactionID': (++_transactionId).toString(),
        ...?params,
      };

      final response = await _httpClient
          .put(uri, body: body)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw AlpacaException(
            'HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      if (json['ErrorNumber'] != 0) {
        throw AlpacaException(
            'Alpaca error ${json['ErrorNumber']}: ${json['ErrorMessage']}');
      }

      return json;
    });
  }

  /// Execute an operation with retry and circuit breaker protection
  Future<T> _executeWithResilience<T>(Future<T> Function() operation) async {
    return _circuitBreaker.execute(() async {
      return withRetry(
        operation,
        const RetryConfig(
          maxAttempts: 3,
          initialDelay: Duration(milliseconds: 500),
          maxDelay: Duration(seconds: 5),
          multiplier: 2.0,
        ),
        shouldRetry: (e) {
          // Retry on network errors and timeouts, but not on device errors
          return isNetworkException(e);
        },
      );
    });
  }

  // =========================================================================
  // Common Device Properties
  // =========================================================================

  /// Check if device is connected
  Future<bool> get connected async {
    final result = await get('connected');
    return result['Value'] as bool;
  }

  /// Connect to the device
  Future<void> connect() async {
    await put('connected', {'Connected': 'true'});
  }

  /// Disconnect from the device
  Future<void> disconnect() async {
    await put('connected', {'Connected': 'false'});
  }

  /// Get device name
  Future<String> get name async {
    final result = await get('name');
    return result['Value'] as String;
  }

  /// Get device description
  Future<String> get description async {
    final result = await get('description');
    return result['Value'] as String;
  }

  /// Get driver version
  Future<String> get driverVersion async {
    final result = await get('driverversion');
    return result['Value'] as String;
  }

  /// Dispose of resources
  void dispose() {
    _httpClient.close();
    // Reset circuit breaker on dispose
    _circuitBreaker.reset();
  }

  /// Manually reset the circuit breaker (e.g., after fixing connectivity)
  void resetCircuitBreaker() {
    _circuitBreaker.reset();
  }
}

/// Exception for Alpaca errors
class AlpacaException implements Exception {
  final String message;
  AlpacaException(this.message);

  @override
  String toString() => 'AlpacaException: $message';
}

// ============================================================================
// Specialized Clients
// ============================================================================

/// Client for Alpaca cameras
class AlpacaCameraClient extends AlpacaClient {
  AlpacaCameraClient(super.device);

  Future<double?> get ccdTemperature async {
    try {
      final result = await get('ccdtemperature');
      return (result['Value'] as num?)?.toDouble();
    } catch (e) {
      return null;
    }
  }

  Future<bool> get coolerOn async {
    final result = await get('cooleron');
    return result['Value'] as bool;
  }

  Future<void> setCoolerOn(bool value) async {
    await put('cooleron', {'CoolerOn': value.toString()});
  }

  Future<double?> get coolerPower async {
    try {
      final result = await get('coolerpower');
      return (result['Value'] as num?)?.toDouble();
    } catch (e) {
      return null;
    }
  }

  Future<double> get setPoint async {
    final result = await get('setccdtemperature');
    return (result['Value'] as num).toDouble();
  }

  Future<void> setSetPoint(double temp) async {
    await put('setccdtemperature', {'SetCCDTemperature': temp.toString()});
  }

  Future<int> get binX async {
    final result = await get('binx');
    return result['Value'] as int;
  }

  Future<int> get binY async {
    final result = await get('biny');
    return result['Value'] as int;
  }

  Future<void> setBinning(int x, int y) async {
    await put('binx', {'BinX': x.toString()});
    await put('biny', {'BinY': y.toString()});
  }

  Future<int> get gain async {
    final result = await get('gain');
    return result['Value'] as int;
  }

  Future<void> setGain(int value) async {
    await put('gain', {'Gain': value.toString()});
  }

  Future<void> startExposure(double duration, bool light) async {
    await put('startexposure', {
      'Duration': duration.toString(),
      'Light': light.toString(),
    });
  }

  Future<void> abortExposure() async {
    await put('abortexposure');
  }

  Future<bool> get imageReady async {
    final result = await get('imageready');
    return result['Value'] as bool;
  }
}

/// Client for Alpaca mounts (telescopes)
class AlpacaMountClient extends AlpacaClient {
  AlpacaMountClient(super.device);

  Future<double> get rightAscension async {
    final result = await get('rightascension');
    return (result['Value'] as num).toDouble();
  }

  Future<double> get declination async {
    final result = await get('declination');
    return (result['Value'] as num).toDouble();
  }

  Future<double> get altitude async {
    final result = await get('altitude');
    return (result['Value'] as num).toDouble();
  }

  Future<double> get azimuth async {
    final result = await get('azimuth');
    return (result['Value'] as num).toDouble();
  }

  Future<bool> get tracking async {
    final result = await get('tracking');
    return result['Value'] as bool;
  }

  Future<void> setTracking(bool value) async {
    await put('tracking', {'Tracking': value.toString()});
  }

  Future<bool> get slewing async {
    final result = await get('slewing');
    return result['Value'] as bool;
  }

  Future<bool> get atPark async {
    final result = await get('atpark');
    return result['Value'] as bool;
  }

  Future<void> slewToCoordinates(double ra, double dec) async {
    await put('slewtocoordinatesasync', {
      'RightAscension': ra.toString(),
      'Declination': dec.toString(),
    });
  }

  Future<void> park() async {
    await put('park');
  }

  Future<void> unpark() async {
    await put('unpark');
  }

  Future<void> abortSlew() async {
    await put('abortslew');
  }
}

/// Client for Alpaca focusers
class AlpacaFocuserClient extends AlpacaClient {
  AlpacaFocuserClient(super.device);

  Future<int> get position async {
    final result = await get('position');
    return result['Value'] as int;
  }

  Future<int> get maxStep async {
    final result = await get('maxstep');
    return result['Value'] as int;
  }

  Future<bool> get isMoving async {
    final result = await get('ismoving');
    return result['Value'] as bool;
  }

  Future<double?> get temperature async {
    try {
      final result = await get('temperature');
      return (result['Value'] as num?)?.toDouble();
    } catch (e) {
      return null;
    }
  }

  Future<void> moveTo(int position) async {
    await put('move', {'Position': position.toString()});
  }

  Future<void> halt() async {
    await put('halt');
  }
}

/// Client for Alpaca filter wheels
class AlpacaFilterWheelClient extends AlpacaClient {
  AlpacaFilterWheelClient(super.device);

  Future<int> get position async {
    final result = await get('position');
    return result['Value'] as int;
  }

  Future<void> setPosition(int position) async {
    await put('position', {'Position': position.toString()});
  }

  Future<List<String>> get filterNames async {
    final result = await get('names');
    final names = result['Value'] as List<dynamic>;
    return names.map((e) => e.toString()).toList();
  }
}
