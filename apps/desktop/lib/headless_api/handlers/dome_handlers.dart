import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

/// Handlers for dome control endpoints
///
/// Manages observatory dome operations including shutter control, azimuth slewing,
/// dome-mount synchronization, parking, and home position finding.
class DomeHandlers {
  final ProviderContainer container;

  DomeHandlers(this.container);

  // ===========================================================================
  // Dome Shutter Control
  // ===========================================================================

  /// POST /api/dome/open
  /// Opens the dome shutter.
  /// Request body: { "deviceId": "dome_id" }
  Future<Response> handleDomeOpen(Request request) async {
    print('[API] POST /api/dome/open');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String?;

      if (deviceId == null || deviceId.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({"error": "deviceId is required"}),
          headers: {'content-type': 'application/json'},
        );
      }

      // Check if dome is connected
      final backend = container.read(backendProvider);
      final connectedDevices = await backend.getConnectedDevices();
      final domeConnected = connectedDevices.any(
        (d) => d.id == deviceId && d.deviceType == DeviceType.dome,
      );

      if (!domeConnected) {
        return Response.ok(
          jsonEncode({
            "error": "Dome not connected",
            "deviceId": deviceId,
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // TODO: Implement dome open when backend method is available
      // await backend.domeOpenShutter(deviceId);

      return Response.ok(
        jsonEncode({
          "status": "opening",
          "deviceId": deviceId,
          "message": "Dome shutter opening command sent",
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Dome open error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  /// POST /api/dome/close
  /// Closes the dome shutter.
  /// Request body: { "deviceId": "dome_id" }
  Future<Response> handleDomeClose(Request request) async {
    print('[API] POST /api/dome/close');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String?;

      if (deviceId == null || deviceId.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({"error": "deviceId is required"}),
          headers: {'content-type': 'application/json'},
        );
      }

      // Check if dome is connected
      final backend = container.read(backendProvider);
      final connectedDevices = await backend.getConnectedDevices();
      final domeConnected = connectedDevices.any(
        (d) => d.id == deviceId && d.deviceType == DeviceType.dome,
      );

      if (!domeConnected) {
        return Response.ok(
          jsonEncode({
            "error": "Dome not connected",
            "deviceId": deviceId,
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // TODO: Implement dome close when backend method is available
      // await backend.domeCloseShutter(deviceId);

      return Response.ok(
        jsonEncode({
          "status": "closing",
          "deviceId": deviceId,
          "message": "Dome shutter closing command sent",
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Dome close error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Dome Movement Control
  // ===========================================================================

  /// POST /api/dome/slew
  /// Slews the dome to a specific azimuth.
  /// Request body: { "deviceId": "dome_id", "azimuth": 180.0 }
  Future<Response> handleDomeSlew(Request request) async {
    print('[API] POST /api/dome/slew');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String?;
      final azimuth = (payload['azimuth'] as num?)?.toDouble();

      if (deviceId == null || deviceId.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({"error": "deviceId is required"}),
          headers: {'content-type': 'application/json'},
        );
      }

      if (azimuth == null) {
        return Response.badRequest(
          body: jsonEncode({"error": "azimuth is required (0-360 degrees)"}),
          headers: {'content-type': 'application/json'},
        );
      }

      if (azimuth < 0 || azimuth >= 360) {
        return Response.badRequest(
          body: jsonEncode({"error": "azimuth must be between 0 and 360 degrees"}),
          headers: {'content-type': 'application/json'},
        );
      }

      // Check if dome is connected
      final backend = container.read(backendProvider);
      final connectedDevices = await backend.getConnectedDevices();
      final domeConnected = connectedDevices.any(
        (d) => d.id == deviceId && d.deviceType == DeviceType.dome,
      );

      if (!domeConnected) {
        return Response.ok(
          jsonEncode({
            "error": "Dome not connected",
            "deviceId": deviceId,
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // TODO: Implement dome slew when backend method is available
      // await backend.domeSlewToAzimuth(deviceId, azimuth);

      return Response.ok(
        jsonEncode({
          "status": "slewing",
          "deviceId": deviceId,
          "targetAzimuth": azimuth,
          "message": "Dome slewing to azimuth $azimuth degrees",
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Dome slew error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  /// POST /api/dome/sync
  /// Synchronizes the dome position to follow the mount.
  /// Request body: { "deviceId": "dome_id", "enabled": true }
  Future<Response> handleDomeSync(Request request) async {
    print('[API] POST /api/dome/sync');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String?;
      final enabled = payload['enabled'] as bool? ?? true;

      if (deviceId == null || deviceId.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({"error": "deviceId is required"}),
          headers: {'content-type': 'application/json'},
        );
      }

      // Check if dome is connected
      final backend = container.read(backendProvider);
      final connectedDevices = await backend.getConnectedDevices();
      final domeConnected = connectedDevices.any(
        (d) => d.id == deviceId && d.deviceType == DeviceType.dome,
      );

      if (!domeConnected) {
        return Response.ok(
          jsonEncode({
            "error": "Dome not connected",
            "deviceId": deviceId,
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // TODO: Implement dome sync when backend method is available
      // await backend.domeSyncToMount(deviceId, enabled);

      return Response.ok(
        jsonEncode({
          "status": "ok",
          "deviceId": deviceId,
          "syncEnabled": enabled,
          "message": enabled ? "Dome sync enabled" : "Dome sync disabled",
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Dome sync error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  /// POST /api/dome/park
  /// Parks the dome to its park position.
  /// Request body: { "deviceId": "dome_id" }
  Future<Response> handleDomePark(Request request) async {
    print('[API] POST /api/dome/park');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String?;

      if (deviceId == null || deviceId.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({"error": "deviceId is required"}),
          headers: {'content-type': 'application/json'},
        );
      }

      // Check if dome is connected
      final backend = container.read(backendProvider);
      final connectedDevices = await backend.getConnectedDevices();
      final domeConnected = connectedDevices.any(
        (d) => d.id == deviceId && d.deviceType == DeviceType.dome,
      );

      if (!domeConnected) {
        return Response.ok(
          jsonEncode({
            "error": "Dome not connected",
            "deviceId": deviceId,
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // TODO: Implement dome park when backend method is available
      // await backend.domePark(deviceId);

      return Response.ok(
        jsonEncode({
          "status": "parking",
          "deviceId": deviceId,
          "message": "Dome parking command sent",
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Dome park error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  /// POST /api/dome/home
  /// Moves the dome to its home position.
  /// Request body: { "deviceId": "dome_id" }
  Future<Response> handleDomeHome(Request request) async {
    print('[API] POST /api/dome/home');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String?;

      if (deviceId == null || deviceId.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({"error": "deviceId is required"}),
          headers: {'content-type': 'application/json'},
        );
      }

      // Check if dome is connected
      final backend = container.read(backendProvider);
      final connectedDevices = await backend.getConnectedDevices();
      final domeConnected = connectedDevices.any(
        (d) => d.id == deviceId && d.deviceType == DeviceType.dome,
      );

      if (!domeConnected) {
        return Response.ok(
          jsonEncode({
            "error": "Dome not connected",
            "deviceId": deviceId,
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // TODO: Implement dome find home when backend method is available
      // await backend.domeFindHome(deviceId);

      return Response.ok(
        jsonEncode({
          "status": "homing",
          "deviceId": deviceId,
          "message": "Dome homing command sent",
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Dome home error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  /// POST /api/dome/halt
  /// Immediately stops all dome movement.
  /// Request body: { "deviceId": "dome_id" }
  Future<Response> handleDomeHalt(Request request) async {
    print('[API] POST /api/dome/halt');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String?;

      if (deviceId == null || deviceId.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({"error": "deviceId is required"}),
          headers: {'content-type': 'application/json'},
        );
      }

      // Check if dome is connected
      final backend = container.read(backendProvider);
      final connectedDevices = await backend.getConnectedDevices();
      final domeConnected = connectedDevices.any(
        (d) => d.id == deviceId && d.deviceType == DeviceType.dome,
      );

      if (!domeConnected) {
        return Response.ok(
          jsonEncode({
            "error": "Dome not connected",
            "deviceId": deviceId,
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // TODO: Implement dome halt when backend method is available
      // await backend.domeHalt(deviceId);

      return Response.ok(
        jsonEncode({
          "status": "halted",
          "deviceId": deviceId,
          "message": "Dome movement halted",
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Dome halt error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Dome Status
  // ===========================================================================

  /// GET /api/dome/status
  /// Gets the current dome status.
  /// Query params: deviceId=dome_id
  Future<Response> handleDomeStatus(Request request) async {
    try {
      final deviceId = request.url.queryParameters['deviceId'] ?? '';

      if (deviceId.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({"error": "deviceId query parameter is required"}),
          headers: {'content-type': 'application/json'},
        );
      }

      // Check if dome is connected
      final backend = container.read(backendProvider);
      final connectedDevices = await backend.getConnectedDevices();
      final domeDevice = connectedDevices.firstWhere(
        (d) => d.id == deviceId && d.deviceType == DeviceType.dome,
        orElse: () => DeviceInfo(
          id: '',
          name: '',
          deviceType: DeviceType.dome,
          driverType: DriverType.simulator,
          description: '',
          driverVersion: '',
        ),
      );

      if (domeDevice.id.isEmpty) {
        return Response.ok(
          jsonEncode({
            "connected": false,
            "deviceId": deviceId,
            "error": "Dome not connected",
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // TODO: Get actual dome status when backend method is available
      // final status = await backend.getDomeStatus(deviceId);

      // Return placeholder status
      return Response.ok(
        jsonEncode({
          "connected": true,
          "deviceId": deviceId,
          "deviceName": domeDevice.name,
          "shutterState": "unknown", // open, closed, opening, closing, error, unknown
          "azimuth": 0.0, // Current azimuth in degrees
          "slewing": false, // Whether dome is currently moving
          "atHome": false, // Whether dome is at home position
          "atPark": false, // Whether dome is parked
          "syncEnabled": false, // Whether dome is syncing to mount
          "canSetAzimuth": true,
          "canSetShutter": true,
          "canPark": true,
          "canFindHome": true,
          "canSyncToMount": true,
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Dome status error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  /// GET /api/dome/capabilities
  /// Gets the dome capabilities.
  /// Query params: deviceId=dome_id
  Future<Response> handleDomeCapabilities(Request request) async {
    try {
      final deviceId = request.url.queryParameters['deviceId'] ?? '';

      if (deviceId.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({"error": "deviceId query parameter is required"}),
          headers: {'content-type': 'application/json'},
        );
      }

      // Check if dome is connected
      final backend = container.read(backendProvider);
      final connectedDevices = await backend.getConnectedDevices();
      final domeDevice = connectedDevices.firstWhere(
        (d) => d.id == deviceId && d.deviceType == DeviceType.dome,
        orElse: () => DeviceInfo(
          id: '',
          name: '',
          deviceType: DeviceType.dome,
          driverType: DriverType.simulator,
          description: '',
          driverVersion: '',
        ),
      );

      if (domeDevice.id.isEmpty) {
        return Response.notFound(
          jsonEncode({
            "error": "Dome not found or not connected",
            "deviceId": deviceId,
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // TODO: Get actual dome capabilities when backend method is available
      // final caps = await backend.getDomeCapabilities(deviceId);

      // Return placeholder capabilities
      return Response.ok(
        jsonEncode({
          "deviceId": deviceId,
          "deviceName": domeDevice.name,
          "canSetAzimuth": true,
          "canSlewAsync": true,
          "canSetShutter": true,
          "canSetPark": true,
          "canFindHome": true,
          "canSyncAzimuth": true,
          "azimuthRange": {"min": 0.0, "max": 360.0},
          "slewSpeed": 6.0, // degrees per second
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Dome capabilities error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }
}
