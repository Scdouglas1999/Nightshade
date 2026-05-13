import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';
import '../validation.dart';

/// Handlers for equipment status and capabilities endpoints
class EquipmentHandlers {
  final ProviderContainer container;
  EquipmentHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'EquipmentHandlers');

  // ===========================================================================
  // Equipment Status
  // ===========================================================================

  Future<Response> handleCameraStatus(Request request) async {
    final deviceId = request.url.queryParameters['deviceId'] ?? '';
    final backend = container.read(backendProvider);
    final status = await backend.getCameraStatus(deviceId);
    return jsonOk(status.toJson());
  }

  Future<Response> handleMountStatus(Request request) async {
    final deviceId = request.url.queryParameters['deviceId'] ?? '';
    final backend = container.read(backendProvider);
    final status = await backend.getMountStatus(deviceId);
    return jsonOk(status.toJson());
  }

  Future<Response> handleFocuserStatus(Request request) async {
    final deviceId = request.url.queryParameters['deviceId'] ?? '';
    final backend = container.read(backendProvider);
    final status = await backend.getFocuserStatus(deviceId);
    return jsonOk(status.toJson());
  }

  Future<Response> handleFilterWheelStatus(Request request) async {
    final deviceId = request.url.queryParameters['deviceId'] ?? '';
    final backend = container.read(backendProvider);
    final status = await backend.getFilterWheelStatus(deviceId);
    return jsonOk(status.toJson());
  }

  Future<Response> handleRotatorStatus(Request request) async {
    final deviceId = request.url.queryParameters['deviceId'] ?? '';
    final backend = container.read(backendProvider);
    final status = await backend.getRotatorStatus(deviceId);
    return jsonOk(status.toJson());
  }

  // ===========================================================================
  // Equipment Capabilities
  // ===========================================================================

  Future<Response> handleCameraCapabilities(Request request) async {
    final deviceId = request.url.queryParameters['deviceId'] ?? '';
    final backend = container.read(backendProvider);
    final caps = await backend.getCameraCapabilities(deviceId);
    if (caps == null) {
      return jsonNotFound({
        'error': 'Device not found or capabilities unavailable',
      });
    }
    return jsonOk(caps.toJson());
  }

  Future<Response> handleMountCapabilities(Request request) async {
    final deviceId = request.url.queryParameters['deviceId'] ?? '';
    final backend = container.read(backendProvider);
    final caps = await backend.getMountCapabilities(deviceId);
    if (caps == null) {
      return jsonNotFound({
        'error': 'Device not found or capabilities unavailable',
      });
    }
    return jsonOk(caps.toJson());
  }

  Future<Response> handleFocuserCapabilities(Request request) async {
    final deviceId = request.url.queryParameters['deviceId'] ?? '';
    final backend = container.read(backendProvider);
    final caps = await backend.getFocuserCapabilities(deviceId);
    if (caps == null) {
      return jsonNotFound({
        'error': 'Device not found or capabilities unavailable',
      });
    }
    return jsonOk(caps.toJson());
  }

  Future<Response> handleFilterWheelCapabilities(Request request) async {
    final deviceId = request.url.queryParameters['deviceId'] ?? '';
    final backend = container.read(backendProvider);
    final caps = await backend.getFilterWheelCapabilities(deviceId);
    if (caps == null) {
      return jsonNotFound({
        'error': 'Device not found or capabilities unavailable',
      });
    }
    return jsonOk(caps.toJson());
  }

  Future<Response> handleRotatorCapabilities(Request request) async {
    final deviceId = request.url.queryParameters['deviceId'] ?? '';
    final backend = container.read(backendProvider);
    final caps = await backend.getRotatorCapabilities(deviceId);
    if (caps == null) {
      return jsonNotFound({
        'error': 'Device not found or capabilities unavailable',
      });
    }
    return jsonOk(caps.toJson());
  }

  // ===========================================================================
  // Device Health Monitoring
  // ===========================================================================

  Future<Response> handleStartDeviceHeartbeat(Request request) async {
    _logInfo('[API] POST /api/device/heartbeat/start');
    final payload = await readJsonObject(request);
    final deviceTypeStr = requireString(payload, 'device_type');
    final deviceId = requireString(payload, 'device_id');
    final intervalMs = requireInt(payload, 'interval_ms');

    final deviceType = _parseDeviceType(deviceTypeStr);
    if (deviceType == null) {
      throw BadRequestError(
        field: 'device_type',
        expected: 'one of: ${DeviceType.values.map((e) => e.name).join(', ')}',
        message: 'Invalid device type: $deviceTypeStr',
      );
    }

    final backend = container.read(backendProvider);
    await backend.startDeviceHeartbeat(
      deviceType: deviceType,
      deviceId: deviceId,
      intervalMs: intervalMs,
    );
    return jsonOk({'status': 'started'});
  }

  Future<Response> handleStopDeviceHeartbeat(Request request) async {
    _logInfo('[API] POST /api/device/heartbeat/stop');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'device_id');

    final backend = container.read(backendProvider);
    await backend.stopDeviceHeartbeat(deviceId);
    return jsonOk({'status': 'stopped'});
  }

  Future<Response> handleGetDeviceHealth(
      Request request, String deviceId) async {
    final backend = container.read(backendProvider);
    final (lastComm, isHealthy) = await backend.getDeviceHealth(deviceId);
    return jsonOk({
      'last_successful_comm': lastComm,
      'is_healthy': isHealthy,
    });
  }

  DeviceType? _parseDeviceType(String type) {
    try {
      return DeviceType.values
          .firstWhere((e) => e.name.toLowerCase() == type.toLowerCase());
    } on StateError {
      // Why: `firstWhere` throws StateError on no-match. We deliberately
      // return null so the caller can produce a structured 400 with the
      // accepted device-type list, rather than letting the exception
      // bubble as a generic 500.
      return null;
    }
  }
}
