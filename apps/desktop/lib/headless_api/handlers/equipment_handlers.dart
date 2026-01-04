import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

/// Handlers for equipment status and capabilities endpoints
class EquipmentHandlers {
  final ProviderContainer container;

  EquipmentHandlers(this.container);

  // ===========================================================================
  // Equipment Status
  // ===========================================================================

  Future<Response> handleCameraStatus(Request request) async {
    try {
      final deviceId = request.url.queryParameters['deviceId'] ?? '';
      final backend = container.read(backendProvider);
      final status = await backend.getCameraStatus(deviceId);
      return Response.ok(
        jsonEncode(status.toJson()),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Camera status error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleMountStatus(Request request) async {
    try {
      final deviceId = request.url.queryParameters['deviceId'] ?? '';
      final backend = container.read(backendProvider);
      final status = await backend.getMountStatus(deviceId);
      return Response.ok(
        jsonEncode(status.toJson()),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Mount status error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleFocuserStatus(Request request) async {
    try {
      final deviceId = request.url.queryParameters['deviceId'] ?? '';
      final backend = container.read(backendProvider);
      final status = await backend.getFocuserStatus(deviceId);
      return Response.ok(
        jsonEncode(status.toJson()),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Focuser status error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleFilterWheelStatus(Request request) async {
    try {
      final deviceId = request.url.queryParameters['deviceId'] ?? '';
      final backend = container.read(backendProvider);
      final status = await backend.getFilterWheelStatus(deviceId);
      return Response.ok(
        jsonEncode(status.toJson()),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Filter wheel status error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleRotatorStatus(Request request) async {
    try {
      final deviceId = request.url.queryParameters['deviceId'] ?? '';
      final backend = container.read(backendProvider);
      final status = await backend.getRotatorStatus(deviceId);
      return Response.ok(
        jsonEncode(status.toJson()),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Rotator status error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Equipment Capabilities
  // ===========================================================================

  Future<Response> handleCameraCapabilities(Request request) async {
    try {
      final deviceId = request.url.queryParameters['deviceId'] ?? '';
      final backend = container.read(backendProvider);
      final caps = await backend.getCameraCapabilities(deviceId);
      if (caps == null) {
        return Response.notFound(jsonEncode({"error": "Device not found or capabilities unavailable"}));
      }
      return Response.ok(
        jsonEncode(caps.toJson()),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Camera capabilities error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleMountCapabilities(Request request) async {
    try {
      final deviceId = request.url.queryParameters['deviceId'] ?? '';
      final backend = container.read(backendProvider);
      final caps = await backend.getMountCapabilities(deviceId);
      if (caps == null) {
        return Response.notFound(jsonEncode({"error": "Device not found or capabilities unavailable"}));
      }
      return Response.ok(
        jsonEncode(caps.toJson()),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Mount capabilities error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleFocuserCapabilities(Request request) async {
    try {
      final deviceId = request.url.queryParameters['deviceId'] ?? '';
      final backend = container.read(backendProvider);
      final caps = await backend.getFocuserCapabilities(deviceId);
      if (caps == null) {
        return Response.notFound(jsonEncode({"error": "Device not found or capabilities unavailable"}));
      }
      return Response.ok(
        jsonEncode(caps.toJson()),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Focuser capabilities error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleFilterWheelCapabilities(Request request) async {
    try {
      final deviceId = request.url.queryParameters['deviceId'] ?? '';
      final backend = container.read(backendProvider);
      final caps = await backend.getFilterWheelCapabilities(deviceId);
      if (caps == null) {
        return Response.notFound(jsonEncode({"error": "Device not found or capabilities unavailable"}));
      }
      return Response.ok(
        jsonEncode(caps.toJson()),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Filter wheel capabilities error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleRotatorCapabilities(Request request) async {
    try {
      final deviceId = request.url.queryParameters['deviceId'] ?? '';
      final backend = container.read(backendProvider);
      final caps = await backend.getRotatorCapabilities(deviceId);
      if (caps == null) {
        return Response.notFound(jsonEncode({"error": "Device not found or capabilities unavailable"}));
      }
      return Response.ok(
        jsonEncode(caps.toJson()),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Rotator capabilities error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Device Health Monitoring
  // ===========================================================================

  Future<Response> handleStartDeviceHeartbeat(Request request) async {
    print('[API] POST /api/device/heartbeat/start');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceTypeStr = payload['device_type'] as String;
      final deviceId = payload['device_id'] as String;
      final intervalMs = payload['interval_ms'] as int;

      final deviceType = _parseDeviceType(deviceTypeStr);
      if (deviceType == null) {
        return Response.badRequest(
          body: jsonEncode({"error": "Invalid device type: $deviceTypeStr"}),
          headers: {'content-type': 'application/json'},
        );
      }

      final backend = container.read(backendProvider);
      await backend.startDeviceHeartbeat(
        deviceType: deviceType,
        deviceId: deviceId,
        intervalMs: intervalMs,
      );
      return Response.ok(
        jsonEncode({"status": "started"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Start device heartbeat error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleStopDeviceHeartbeat(Request request) async {
    print('[API] POST /api/device/heartbeat/stop');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['device_id'] as String;

      final backend = container.read(backendProvider);
      await backend.stopDeviceHeartbeat(deviceId);
      return Response.ok(
        jsonEncode({"status": "stopped"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Stop device heartbeat error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleGetDeviceHealth(Request request, String deviceId) async {
    try {
      final backend = container.read(backendProvider);
      final (lastComm, isHealthy) = await backend.getDeviceHealth(deviceId);
      return Response.ok(
        jsonEncode({
          "last_successful_comm": lastComm,
          "is_healthy": isHealthy,
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Get device health error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  DeviceType? _parseDeviceType(String type) {
    try {
      return DeviceType.values
          .firstWhere((e) => e.name.toLowerCase() == type.toLowerCase());
    } catch (_) {
      return null;
    }
  }
}
