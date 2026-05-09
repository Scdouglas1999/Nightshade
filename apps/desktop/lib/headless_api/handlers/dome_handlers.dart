import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge;
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';

/// Handlers for dome control endpoints
class DomeHandlers {
  final ProviderContainer container;

  DomeHandlers(this.container);

  Future<bool> _isConnectedDome(String deviceId) async {
    final backend = container.read(backendProvider);
    final connectedDevices = await backend.getConnectedDevices();
    return connectedDevices.any(
      (d) => d.id == deviceId && d.deviceType == DeviceType.dome,
    );
  }

  Response _notImplemented(String operation) {
    return jsonNotImplemented({
      'error': '$operation is not supported by the current native API',
    });
  }

  String _mapShutterState(bridge.ShutterState state) {
    switch (state) {
      case bridge.ShutterState.open:
        return 'open';
      case bridge.ShutterState.closed:
        return 'closed';
      case bridge.ShutterState.opening:
        return 'opening';
      case bridge.ShutterState.closing:
        return 'closing';
      case bridge.ShutterState.error:
        return 'error';
      case bridge.ShutterState.unknown:
        return 'unknown';
    }
  }

  String _mapShutterStatus(bridge.ShutterStatus? status) {
    if (status == null) return 'unknown';
    switch (status) {
      case bridge.ShutterStatus.open:
        return 'open';
      case bridge.ShutterStatus.closed:
        return 'closed';
      case bridge.ShutterStatus.opening:
        return 'opening';
      case bridge.ShutterStatus.closing:
        return 'closing';
      case bridge.ShutterStatus.unknown:
        return 'unknown';
    }
  }

  /// POST /api/dome/open
  Future<Response> handleDomeOpen(Request request) async {
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String?;
      if (deviceId == null || deviceId.isEmpty) {
        return jsonBadRequest({'error': 'deviceId is required'});
      }
      if (!await _isConnectedDome(deviceId)) {
        return jsonNotFound({
          'error': 'Dome not connected',
          'deviceId': deviceId,
        });
      }
      await bridge.apiDomeOpenShutter(deviceId: deviceId);
      return jsonOk({'status': 'opening', 'deviceId': deviceId});
    } catch (e) {
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  /// POST /api/dome/close
  Future<Response> handleDomeClose(Request request) async {
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String?;
      if (deviceId == null || deviceId.isEmpty) {
        return jsonBadRequest({'error': 'deviceId is required'});
      }
      if (!await _isConnectedDome(deviceId)) {
        return jsonNotFound({
          'error': 'Dome not connected',
          'deviceId': deviceId,
        });
      }
      await bridge.apiDomeCloseShutter(deviceId: deviceId);
      return jsonOk({'status': 'closing', 'deviceId': deviceId});
    } catch (e) {
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  /// POST /api/dome/slew
  Future<Response> handleDomeSlew(Request request) async {
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String?;
      final azimuth = (payload['azimuth'] as num?)?.toDouble();
      if (deviceId == null || deviceId.isEmpty) {
        return jsonBadRequest({'error': 'deviceId is required'});
      }
      if (azimuth == null || azimuth < 0 || azimuth >= 360) {
        return jsonBadRequest({
          'error': 'azimuth must be between 0 and 360 degrees',
        });
      }
      if (!await _isConnectedDome(deviceId)) {
        return jsonNotFound({
          'error': 'Dome not connected',
          'deviceId': deviceId,
        });
      }
      await bridge.apiDomeSlewToAzimuth(deviceId: deviceId, azimuth: azimuth);
      return jsonOk({
        'status': 'slewing',
        'deviceId': deviceId,
        'targetAzimuth': azimuth
      });
    } catch (e) {
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  /// POST /api/dome/sync
  Future<Response> handleDomeSync(Request request) async {
    return _notImplemented('Dome sync');
  }

  /// POST /api/dome/park
  Future<Response> handleDomePark(Request request) async {
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String?;
      if (deviceId == null || deviceId.isEmpty) {
        return jsonBadRequest({'error': 'deviceId is required'});
      }
      if (!await _isConnectedDome(deviceId)) {
        return jsonNotFound({
          'error': 'Dome not connected',
          'deviceId': deviceId,
        });
      }
      await bridge.apiDomePark(deviceId: deviceId);
      return jsonOk({'status': 'parking', 'deviceId': deviceId});
    } catch (e) {
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  /// POST /api/dome/home
  Future<Response> handleDomeHome(Request request) async {
    return _notImplemented('Dome home');
  }

  /// POST /api/dome/halt
  Future<Response> handleDomeHalt(Request request) async {
    return _notImplemented('Dome halt');
  }

  /// GET /api/dome/status
  Future<Response> handleDomeStatus(Request request) async {
    try {
      final deviceId = request.url.queryParameters['deviceId'] ?? '';
      if (deviceId.isEmpty) {
        return jsonBadRequest({
          'error': 'deviceId query parameter is required',
        });
      }
      if (!await _isConnectedDome(deviceId)) {
        return jsonNotFound(
          {
            'connected': false,
            'deviceId': deviceId,
            'error': 'Dome not connected'
          },
        );
      }

      final status = await bridge.apiGetDomeStatus(deviceId: deviceId);
      return jsonOk({
        'connected': status.connected,
        'deviceId': deviceId,
        'shutterState': _mapShutterState(status.shutterStatus),
        'azimuth': status.azimuth,
        'altitude': status.altitude,
        'slewing': status.slewing,
        'atHome': status.atHome,
        'atPark': status.atPark,
        'canSetAltitude': status.canSetAltitude,
        'canSetAzimuth': status.canSetAzimuth,
        'canSetShutter': status.canSetShutter,
        'canSyncToMount': status.canSlave,
        'syncEnabled': status.isSlaved,
      });
    } catch (e) {
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  /// GET /api/dome/capabilities
  Future<Response> handleDomeCapabilities(Request request) async {
    try {
      final deviceId = request.url.queryParameters['deviceId'] ?? '';
      if (deviceId.isEmpty) {
        return jsonBadRequest({
          'error': 'deviceId query parameter is required',
        });
      }
      if (!await _isConnectedDome(deviceId)) {
        return jsonNotFound(
          {'error': 'Dome not found or not connected', 'deviceId': deviceId},
        );
      }

      final caps = await bridge.apiGetDomeCapabilities(deviceId: deviceId);
      return jsonOk({
        'deviceId': deviceId,
        'canSetAzimuth': caps.canSetAzimuth,
        'canSetShutter': caps.canSetShutter,
        'canPark': caps.canPark,
        'canFindHome': caps.canFindHome,
        'canSyncAzimuth': caps.canSyncAzimuth,
        'canSetSlave': caps.canSlave,
        'canAbort': caps.canAbort,
        'slewing': caps.slewing,
        'atHome': caps.atHome,
        'atPark': caps.atPark,
        'slaved': caps.slaved,
        'azimuth': caps.azimuth,
        'shutterStatus': _mapShutterStatus(caps.shutterStatus),
      });
    } catch (e) {
      return jsonInternalServerError({'error': e.toString()});
    }
  }
}
