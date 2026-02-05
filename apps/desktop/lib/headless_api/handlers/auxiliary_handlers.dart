import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

/// Handlers for auxiliary device endpoints (Switch and Cover Calibrator)
///
/// Switch devices provide control over observatory equipment like dew heaters,
/// flat panel lights, fans, or custom relay boards.
///
/// Cover Calibrators combine a dust cover mechanism with a flat field light source,
/// commonly used for taking flat frames and protecting the optical train.
class AuxiliaryHandlers {
  final ProviderContainer container;

  AuxiliaryHandlers(this.container);

  // ===========================================================================
  // Switch Control
  // ===========================================================================

  /// GET /api/switch/status
  /// Gets the status of all switches on a switch device.
  /// Query params: deviceId=switch_id
  Future<Response> handleSwitchStatus(Request request) async {
    try {
      final deviceId = request.url.queryParameters['deviceId'] ?? '';

      if (deviceId.isEmpty) {
        // Return status from all connected switch devices
        final backend = container.read(backendProvider);
        final connectedDevices = await backend.getConnectedDevices();

        final switchDevices = connectedDevices.where(
          (d) => d.deviceType == DeviceType.switch_,
        ).toList();

        if (switchDevices.isEmpty) {
          return Response.ok(
            jsonEncode({
              "devicesConnected": 0,
              "devices": <Map<String, dynamic>>[],
              "message": "No switch devices connected",
            }),
            headers: {'content-type': 'application/json'},
          );
        }

        // TODO: Get actual switch status when backend method is available
        final deviceStatuses = switchDevices.map((d) => {
          'deviceId': d.id,
          'deviceName': d.name,
          'connected': true,
          'switches': _getPlaceholderSwitches(),
        }).toList();

        return Response.ok(
          jsonEncode({
            "devicesConnected": switchDevices.length,
            "devices": deviceStatuses,
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Return status for specific device
      final backend = container.read(backendProvider);
      final connectedDevices = await backend.getConnectedDevices();

      final switchDevice = connectedDevices.firstWhere(
        (d) => d.id == deviceId && d.deviceType == DeviceType.switch_,
        orElse: () => DeviceInfo(
          id: '',
          name: '',
          deviceType: DeviceType.switch_,
          driverType: DriverType.simulator,
          description: '',
          driverVersion: '',
        ),
      );

      if (switchDevice.id.isEmpty) {
        return Response.ok(
          jsonEncode({
            "connected": false,
            "deviceId": deviceId,
            "error": "Switch device not connected",
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // TODO: Get actual switch status when backend method is available
      // final status = await backend.getSwitchStatus(deviceId);

      return Response.ok(
        jsonEncode({
          "connected": true,
          "deviceId": deviceId,
          "deviceName": switchDevice.name,
          "switchCount": 8, // Placeholder
          "switches": _getPlaceholderSwitches(),
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Switch status error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  /// POST /api/switch/set
  /// Sets the value of a specific switch.
  /// Request body: { "deviceId": "switch_id", "switchId": 0, "value": true } (for boolean)
  /// Request body: { "deviceId": "switch_id", "switchId": 0, "value": 75.0 } (for analog)
  Future<Response> handleSwitchSet(Request request) async {
    print('[API] POST /api/switch/set');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String?;
      final switchId = payload['switchId'] as int?;
      final value = payload['value']; // Can be bool, int, or double

      if (deviceId == null || deviceId.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({"error": "deviceId is required"}),
          headers: {'content-type': 'application/json'},
        );
      }

      if (switchId == null) {
        return Response.badRequest(
          body: jsonEncode({"error": "switchId is required"}),
          headers: {'content-type': 'application/json'},
        );
      }

      if (value == null) {
        return Response.badRequest(
          body: jsonEncode({"error": "value is required"}),
          headers: {'content-type': 'application/json'},
        );
      }

      // Check if switch device is connected
      final backend = container.read(backendProvider);
      final connectedDevices = await backend.getConnectedDevices();
      final switchConnected = connectedDevices.any(
        (d) => d.id == deviceId && d.deviceType == DeviceType.switch_,
      );

      if (!switchConnected) {
        return Response.ok(
          jsonEncode({
            "error": "Switch device not connected",
            "deviceId": deviceId,
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // TODO: Implement switch set when backend method is available
      // if (value is bool) {
      //   await backend.setSwitchValue(deviceId, switchId, value);
      // } else {
      //   await backend.setSwitchAnalogValue(deviceId, switchId, (value as num).toDouble());
      // }

      return Response.ok(
        jsonEncode({
          "status": "ok",
          "deviceId": deviceId,
          "switchId": switchId,
          "value": value,
          "message": "Switch $switchId set to $value",
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Switch set error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Cover Calibrator Control
  // ===========================================================================

  /// GET /api/cover/status
  /// Gets the cover calibrator status.
  /// Query params: deviceId=cover_calibrator_id
  Future<Response> handleCoverStatus(Request request) async {
    try {
      final deviceId = request.url.queryParameters['deviceId'] ?? '';

      if (deviceId.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({"error": "deviceId query parameter is required"}),
          headers: {'content-type': 'application/json'},
        );
      }

      // Check if cover calibrator is connected
      final backend = container.read(backendProvider);
      final connectedDevices = await backend.getConnectedDevices();

      final coverDevice = connectedDevices.firstWhere(
        (d) => d.id == deviceId && d.deviceType == DeviceType.coverCalibrator,
        orElse: () => DeviceInfo(
          id: '',
          name: '',
          deviceType: DeviceType.coverCalibrator,
          driverType: DriverType.simulator,
          description: '',
          driverVersion: '',
        ),
      );

      if (coverDevice.id.isEmpty) {
        return Response.ok(
          jsonEncode({
            "connected": false,
            "deviceId": deviceId,
            "error": "Cover calibrator not connected",
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // TODO: Get actual cover calibrator status when backend method is available
      // final status = await backend.getCoverCalibratorStatus(deviceId);

      return Response.ok(
        jsonEncode({
          "connected": true,
          "deviceId": deviceId,
          "deviceName": coverDevice.name,
          "coverState": "unknown", // unknown, notPresent, closed, moving, open, error
          "calibratorState": "off", // unknown, notPresent, off, notReady, ready, error
          "brightness": 0, // 0-255 or device-specific range
          "maxBrightness": 255,
          "hasCover": true,
          "hasCalibrator": true,
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Cover status error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  /// POST /api/cover/open
  /// Opens the cover.
  /// Request body: { "deviceId": "cover_calibrator_id" }
  Future<Response> handleCoverOpen(Request request) async {
    print('[API] POST /api/cover/open');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String?;

      if (deviceId == null || deviceId.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({"error": "deviceId is required"}),
          headers: {'content-type': 'application/json'},
        );
      }

      // Check if cover calibrator is connected
      final backend = container.read(backendProvider);
      final connectedDevices = await backend.getConnectedDevices();
      final coverConnected = connectedDevices.any(
        (d) => d.id == deviceId && d.deviceType == DeviceType.coverCalibrator,
      );

      if (!coverConnected) {
        return Response.ok(
          jsonEncode({
            "error": "Cover calibrator not connected",
            "deviceId": deviceId,
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // TODO: Implement cover open when backend method is available
      // await backend.coverOpen(deviceId);

      return Response.ok(
        jsonEncode({
          "status": "opening",
          "deviceId": deviceId,
          "message": "Cover opening command sent",
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Cover open error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  /// POST /api/cover/close
  /// Closes the cover.
  /// Request body: { "deviceId": "cover_calibrator_id" }
  Future<Response> handleCoverClose(Request request) async {
    print('[API] POST /api/cover/close');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String?;

      if (deviceId == null || deviceId.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({"error": "deviceId is required"}),
          headers: {'content-type': 'application/json'},
        );
      }

      // Check if cover calibrator is connected
      final backend = container.read(backendProvider);
      final connectedDevices = await backend.getConnectedDevices();
      final coverConnected = connectedDevices.any(
        (d) => d.id == deviceId && d.deviceType == DeviceType.coverCalibrator,
      );

      if (!coverConnected) {
        return Response.ok(
          jsonEncode({
            "error": "Cover calibrator not connected",
            "deviceId": deviceId,
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // TODO: Implement cover close when backend method is available
      // await backend.coverClose(deviceId);

      return Response.ok(
        jsonEncode({
          "status": "closing",
          "deviceId": deviceId,
          "message": "Cover closing command sent",
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Cover close error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  /// POST /api/cover/brightness
  /// Sets the calibrator brightness level.
  /// Request body: { "deviceId": "cover_calibrator_id", "brightness": 128 }
  Future<Response> handleCoverBrightness(Request request) async {
    print('[API] POST /api/cover/brightness');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String?;
      final brightness = payload['brightness'] as int?;

      if (deviceId == null || deviceId.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({"error": "deviceId is required"}),
          headers: {'content-type': 'application/json'},
        );
      }

      if (brightness == null) {
        return Response.badRequest(
          body: jsonEncode({"error": "brightness is required (0-255)"}),
          headers: {'content-type': 'application/json'},
        );
      }

      if (brightness < 0 || brightness > 255) {
        return Response.badRequest(
          body: jsonEncode({"error": "brightness must be between 0 and 255"}),
          headers: {'content-type': 'application/json'},
        );
      }

      // Check if cover calibrator is connected
      final backend = container.read(backendProvider);
      final connectedDevices = await backend.getConnectedDevices();
      final coverConnected = connectedDevices.any(
        (d) => d.id == deviceId && d.deviceType == DeviceType.coverCalibrator,
      );

      if (!coverConnected) {
        return Response.ok(
          jsonEncode({
            "error": "Cover calibrator not connected",
            "deviceId": deviceId,
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // TODO: Implement calibrator brightness when backend method is available
      // await backend.calibratorSetBrightness(deviceId, brightness);

      return Response.ok(
        jsonEncode({
          "status": "ok",
          "deviceId": deviceId,
          "brightness": brightness,
          "message": "Calibrator brightness set to $brightness",
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Cover brightness error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  /// POST /api/cover/calibrator-on
  /// Turns the calibrator light on (at current or specified brightness).
  /// Request body: { "deviceId": "cover_calibrator_id", "brightness": 128 } (brightness optional)
  Future<Response> handleCalibratorOn(Request request) async {
    print('[API] POST /api/cover/calibrator-on');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String?;
      final brightness = payload['brightness'] as int?;

      if (deviceId == null || deviceId.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({"error": "deviceId is required"}),
          headers: {'content-type': 'application/json'},
        );
      }

      if (brightness != null && (brightness < 0 || brightness > 255)) {
        return Response.badRequest(
          body: jsonEncode({"error": "brightness must be between 0 and 255"}),
          headers: {'content-type': 'application/json'},
        );
      }

      // Check if cover calibrator is connected
      final backend = container.read(backendProvider);
      final connectedDevices = await backend.getConnectedDevices();
      final coverConnected = connectedDevices.any(
        (d) => d.id == deviceId && d.deviceType == DeviceType.coverCalibrator,
      );

      if (!coverConnected) {
        return Response.ok(
          jsonEncode({
            "error": "Cover calibrator not connected",
            "deviceId": deviceId,
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // TODO: Implement calibrator on when backend method is available
      // await backend.calibratorOn(deviceId, brightness);

      return Response.ok(
        jsonEncode({
          "status": "on",
          "deviceId": deviceId,
          "brightness": brightness ?? 128,
          "message": "Calibrator turned on${brightness != null ? ' at brightness $brightness' : ''}",
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Calibrator on error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  /// POST /api/cover/calibrator-off
  /// Turns the calibrator light off.
  /// Request body: { "deviceId": "cover_calibrator_id" }
  Future<Response> handleCalibratorOff(Request request) async {
    print('[API] POST /api/cover/calibrator-off');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String?;

      if (deviceId == null || deviceId.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({"error": "deviceId is required"}),
          headers: {'content-type': 'application/json'},
        );
      }

      // Check if cover calibrator is connected
      final backend = container.read(backendProvider);
      final connectedDevices = await backend.getConnectedDevices();
      final coverConnected = connectedDevices.any(
        (d) => d.id == deviceId && d.deviceType == DeviceType.coverCalibrator,
      );

      if (!coverConnected) {
        return Response.ok(
          jsonEncode({
            "error": "Cover calibrator not connected",
            "deviceId": deviceId,
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // TODO: Implement calibrator off when backend method is available
      // await backend.calibratorOff(deviceId);

      return Response.ok(
        jsonEncode({
          "status": "off",
          "deviceId": deviceId,
          "message": "Calibrator turned off",
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Calibrator off error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Helper Methods
  // ===========================================================================

  /// Returns placeholder switch data for demonstration.
  List<Map<String, dynamic>> _getPlaceholderSwitches() {
    return [
      {
        "id": 0,
        "name": "Dew Heater 1",
        "type": "boolean",
        "value": false,
        "canWrite": true,
        "description": "Primary dew heater for main OTA",
      },
      {
        "id": 1,
        "name": "Dew Heater 2",
        "type": "boolean",
        "value": false,
        "canWrite": true,
        "description": "Secondary dew heater for guide scope",
      },
      {
        "id": 2,
        "name": "Flat Panel",
        "type": "boolean",
        "value": false,
        "canWrite": true,
        "description": "Flat field panel power",
      },
      {
        "id": 3,
        "name": "USB Hub Power",
        "type": "boolean",
        "value": true,
        "canWrite": true,
        "description": "USB hub power control",
      },
      {
        "id": 4,
        "name": "Dew Heater 1 Power",
        "type": "analog",
        "value": 0.0,
        "minValue": 0.0,
        "maxValue": 100.0,
        "step": 1.0,
        "canWrite": true,
        "description": "Dew heater power percentage",
      },
    ];
  }
}
