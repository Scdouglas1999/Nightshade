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

  void _logWarning(String message, {Map<String, Object?>? fields}) => _logger
      .warning(message, source: 'DeviceDiscoveryHandlers', fields: fields);
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
      final backend = container.read(deviceBackendProvider);

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
            discoveryErrors[deviceType.name] = _sanitizeDiscoveryError(e);
            _logWarning(
              '[API][$requestId] Discovery failed for ${deviceType.name}: $e',
              fields: {
                'requestId': requestId,
                'deviceType': deviceType.name,
                'error': '$e',
                'stack': '$stackTrace',
              },
            );
          }
        }
      } else {
        // Why parallel fan-out: the native sweep probes every vendor SDK once
        // per DeviceType, so a sequential loop over all 11 types serialized
        // ~1 minute of mostly-idle I/O wait. Each `discoverDevices` call is an
        // independent async FFI round-trip, so we fan them out concurrently and
        // join with `Future.wait`, cutting wall-clock time to the slowest single
        // type. Correctness does NOT depend on completion order: every future
        // resolves to a (DeviceType, devices) pair, and the merge below is a
        // pure id-keyed reduction that is associative/commutative over the
        // result list. The per-type try/catch still maps each failure to
        // `discoveryErrors[dt.name]` with the exact same log fields, so the
        // §2.26 "surface persistent driver failures" contract is preserved.
        //
        // `discoveryErrors` writes from the per-future catch blocks are safe
        // without a lock: Dart's event loop is single-threaded, so each future's
        // catch body runs to completion as one atomic turn — there is no
        // interleaving that could drop or clobber a sibling's entry.
        final futures = DeviceType.values.map((dt) async {
          try {
            return MapEntry(dt, await backend.discoverDevices(dt));
          } catch (e, stackTrace) {
            discoveryErrors[dt.name] = _sanitizeDiscoveryError(e);
            _logWarning(
              '[API][$requestId] Discovery failed for ${dt.name}: $e',
              fields: {
                'requestId': requestId,
                'deviceType': dt.name,
                'error': '$e',
                'stack': '$stackTrace',
              },
            );
            return MapEntry(dt, const <DeviceInfo>[]);
          }
        });

        final results = await Future.wait(futures);

        // Cross-type dedupe keyed by the globally-unique DeviceInfo.id. A single
        // physical device can be reported under more than one DeviceType sweep
        // (e.g. a multi-function driver enumerated as both camera and filter
        // wheel paths), and a last-write-wins map collapses those to one entry
        // while remaining order-independent across the concurrent results.
        final byId = <String, DeviceInfo>{};
        for (final entry in results) {
          for (final device in entry.value) {
            byId[device.id] = device;
          }
        }
        allDevices = byId.values.toList();
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

  String _sanitizeDiscoveryError(Object error) {
    final raw = error.toString();
    if (raw.startsWith('Exception: ')) {
      return raw.substring('Exception: '.length);
    }
    return raw;
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

      final backend = container.read(deviceBackendProvider);
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

      final backend = container.read(deviceBackendProvider);
      final devices = await backend.discoverAlpacaAtAddress(host, port);
      return jsonOk({'devices': devices.map((d) => d.toJson()).toList()});
    } catch (e, stackTrace) {
      _logError(
          '[API][$requestId] Alpaca address discovery error: $e\n$stackTrace');
      return jsonInternalServerError({'error': 'Internal server error'});
    }
  }

  /// `POST /api/devices/rescan` — force the host to re-enumerate its hardware
  /// buses. Counterpart to the equipment-screen "Rescan equipment" button on a
  /// remote client: the host runs the native hot-plug diff (re-walks vendor
  /// SDKs + ASCOM registry, invalidates its discovery cache, emits
  /// device_discovered/device_lost deltas over the event stream).
  ///
  /// On the host the [deviceBackendProvider] resolves to the FfiBackend, so
  /// `rescanDevices()` here calls the same `apiRescanDevices()` the local
  /// desktop path uses. Mutating action (re-enumeration with side effects), so
  /// it is a POST. Failures surface as 500 rather than a silent no-op.
  Future<Response> handleRescanDevices(Request request) async {
    final requestId = requestIdFrom(request);
    _logInfo('[API][$requestId] POST /api/devices/rescan');
    try {
      final backend = container.read(deviceBackendProvider);
      await backend.rescanDevices();
      return jsonOk({'status': 'ok'});
    } catch (e, stackTrace) {
      _logError('[API][$requestId] Rescan devices error: $e\n$stackTrace');
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
      final backend = container.read(deviceBackendProvider);
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
