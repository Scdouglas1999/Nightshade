/// Device-discovery HTTP handlers for the headless API.
///
/// Owns the read-only catalog endpoints under `/api/devices/*`:
///   * `GET /api/devices` — enumerate every discoverable device, optionally
///     filtered by `?deviceType=`. Per-driver discovery errors are surfaced
///     in the response body (audit §2.26) instead of being silently
///     swallowed.
///   * `GET /api/devices/discover-indi` — point-source discovery against a
///     specific INDI server (`?host=...&port=...`).
///   * `GET /api/devices/discover-alpaca` — same shape for ASCOM Alpaca.
///   * `GET /api/devices/connected` — currently-connected devices.
///
/// The mutating endpoints (`/api/devices/connect` / `/api/devices/disconnect`)
/// live in [DeviceHandlers] (`device_handlers.dart`) because they need the
/// full DeviceService connect pipeline (StateNotifier updates, heartbeat
/// monitoring, recommended-gain auto-apply). Discovery is read-only and has
/// no such dependency, so it lives here.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../request_context.dart';
import '../response_helpers.dart';
import '../utils/device_type_parser.dart';

/// Handlers for read-only device-discovery endpoints. Stateless beyond the
/// [NightshadeBackend] it reads off the [ProviderContainer].
class DeviceDiscoveryHandlers {
  final ProviderContainer container;

  DeviceDiscoveryHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logWarning(String message, {Map<String, Object?>? fields}) =>
      _logger.warning(message, source: 'DeviceDiscoveryHandlers', fields: fields);
  void _logInfo(String message) =>
      _logger.info(message, source: 'DeviceDiscoveryHandlers');
  void _logError(String message) =>
      _logger.error(message, source: 'DeviceDiscoveryHandlers');

  /// `GET /api/devices` — discover every supported device type, optionally
  /// filtered by `?deviceType=`. Per-driver failures are surfaced in
  /// `discoveryErrors` so the dashboard can render an actionable warning
  /// per category (was previously silently swallowed; see §2.26).
  Future<Response> handleGetDevices(Request request) async {
    final requestId = requestIdFrom(request);
    _logInfo('[API][$requestId] GET /api/devices');
    try {
      final deviceTypeStr = request.url.queryParameters['deviceType'];
      final backend = container.read(backendProvider);

      // If no device type specified, discover all device types.
      List<DeviceInfo> allDevices = [];
      // Why surfaced: silent catch_(_) hid persistent driver failures (e.g.
      // missing TouptekSdk DLL, INDI server unreachable) for months because
      // the UI saw an empty discovery list and shrugged (§2.26). Per-type
      // errors now bubble up to the response so the dashboard can render an
      // actionable warning per category.
      final discoveryErrors = <String, String>{};
      if (deviceTypeStr != null) {
        final deviceType = parseDeviceType(deviceTypeStr);
        if (deviceType != null) {
          try {
            allDevices = await backend.discoverDevices(deviceType);
          } catch (e, stackTrace) {
            discoveryErrors[deviceType.name] = e.toString();
            _logWarning(
              '[API][$requestId] Discovery failed for ${deviceType.name}: $e',
              fields: {
                'requestId': requestId,
                'deviceType': deviceType.name,
                'error': e.toString(),
                'stack': stackTrace.toString(),
              },
            );
          }
        }
      } else {
        for (final dt in DeviceType.values) {
          try {
            final devices = await backend.discoverDevices(dt);
            allDevices.addAll(devices);
          } catch (e, stackTrace) {
            discoveryErrors[dt.name] = e.toString();
            _logWarning(
              '[API][$requestId] Discovery failed for ${dt.name}: $e',
              fields: {
                'requestId': requestId,
                'deviceType': dt.name,
                'error': e.toString(),
                'stack': stackTrace.toString(),
              },
            );
          }
        }
      }

      return jsonOk({
        "devices": allDevices
            .map((d) => {
                  'id': d.id,
                  'name': d.name,
                  'deviceType': d.deviceType.name,
                  'driverType': d.driverType.name,
                  'description': d.description,
                })
            .toList(),
        if (discoveryErrors.isNotEmpty) 'discoveryErrors': discoveryErrors,
      });
    } catch (e, stackTrace) {
      _logError('[API][$requestId] Get devices error: $e\n$stackTrace');
      return jsonInternalServerError({"error": "Internal server error"});
    }
  }

  /// `GET /api/devices/discover-indi?host=&port=` — point-source INDI
  /// discovery. Used by the equipment wizard when the user enters an
  /// explicit INDI server address rather than relying on mDNS.
  Future<Response> handleDiscoverIndiAtAddress(Request request) async {
    final requestId = requestIdFrom(request);
    _logInfo('[API][$requestId] GET /api/devices/discover-indi');
    try {
      final host = request.url.queryParameters['host'];
      final port = int.tryParse(request.url.queryParameters['port'] ?? '');
      if (host == null || host.isEmpty || port == null) {
        return jsonBadRequest({'error': 'host and port are required'});
      }

      final backend = container.read(backendProvider);
      final devices = await backend.discoverIndiAtAddress(host, port);
      return jsonOk({'devices': devices.map((d) => d.toJson()).toList()});
    } catch (e, stackTrace) {
      _logError(
          '[API][$requestId] INDI address discovery error: $e\n$stackTrace');
      return jsonInternalServerError({'error': 'Internal server error'});
    }
  }

  /// `GET /api/devices/discover-alpaca?host=&port=` — point-source ASCOM
  /// Alpaca discovery against an explicit host:port.
  Future<Response> handleDiscoverAlpacaAtAddress(Request request) async {
    final requestId = requestIdFrom(request);
    _logInfo('[API][$requestId] GET /api/devices/discover-alpaca');
    try {
      final host = request.url.queryParameters['host'];
      final port = int.tryParse(request.url.queryParameters['port'] ?? '');
      if (host == null || host.isEmpty || port == null) {
        return jsonBadRequest({'error': 'host and port are required'});
      }

      final backend = container.read(backendProvider);
      final devices = await backend.discoverAlpacaAtAddress(host, port);
      return jsonOk({'devices': devices.map((d) => d.toJson()).toList()});
    } catch (e, stackTrace) {
      _logError(
          '[API][$requestId] Alpaca address discovery error: $e\n$stackTrace');
      return jsonInternalServerError({'error': 'Internal server error'});
    }
  }

  /// `GET /api/devices/connected` — currently-connected devices. The
  /// response payload mirrors the GET /api/devices envelope so a client
  /// can render both lists with one renderer.
  Future<Response> handleGetConnectedDevices(Request request) async {
    final requestId = requestIdFrom(request);
    _logInfo('[API][$requestId] GET /api/devices/connected');
    try {
      final backend = container.read(backendProvider);
      final devices = await backend.getConnectedDevices();
      return jsonOk({
        "devices": devices
            .map((d) => {
                  'id': d.id,
                  'name': d.name,
                  'deviceType': d.deviceType.name,
                  'driverType': d.driverType.name,
                  'description': d.description,
                })
            .toList(),
      });
    } catch (e, stackTrace) {
      _logError(
          '[API][$requestId] Get connected devices error: $e\n$stackTrace');
      return jsonInternalServerError({"error": "Internal server error"});
    }
  }
}
