import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

/// Handlers for safety monitor endpoints
///
/// Safety monitors report whether it is safe to continue observing based on
/// various conditions like weather, power status, or custom sensor inputs.
/// Multiple safety monitors can be connected, and all must report "safe"
/// for the system to consider conditions safe for imaging.
class SafetyMonitorHandlers {
  final ProviderContainer container;

  SafetyMonitorHandlers(this.container);

  // ===========================================================================
  // Safety Status
  // ===========================================================================

  /// GET /api/safety/status
  /// Gets the current safety status from all connected safety monitors.
  /// Query params: deviceId=safety_monitor_id (optional - if not provided, returns status from all monitors)
  Future<Response> handleSafetyStatus(Request request) async {
    try {
      final deviceId = request.url.queryParameters['deviceId'];

      final backend = container.read(backendProvider);
      final connectedDevices = await backend.getConnectedDevices();

      // Filter to safety monitors
      final safetyMonitors = connectedDevices.where(
        (d) => d.deviceType == DeviceType.safetyMonitor,
      ).toList();

      if (deviceId != null && deviceId.isNotEmpty) {
        // Return status for specific device
        final monitor = safetyMonitors.firstWhere(
          (d) => d.id == deviceId,
          orElse: () => DeviceInfo(
            id: '',
            name: '',
            deviceType: DeviceType.safetyMonitor,
            driverType: DriverType.simulator,
            description: '',
            driverVersion: '',
          ),
        );

        if (monitor.id.isEmpty) {
          return Response.ok(
            jsonEncode({
              "connected": false,
              "deviceId": deviceId,
              "isSafe": true, // Fail-open: assume safe if not connected
              "error": "Safety monitor not connected",
            }),
            headers: {'content-type': 'application/json'},
          );
        }

        // TODO: Get actual safety status when backend method is available
        // final status = await backend.getSafetyMonitorStatus(deviceId);

        return Response.ok(
          jsonEncode({
            "connected": true,
            "deviceId": deviceId,
            "deviceName": monitor.name,
            "isSafe": true, // Placeholder - actual status from device
            "unsafeReasons": <String>[], // List of reasons if unsafe
            "lastUpdate": DateTime.now().toIso8601String(),
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Return aggregate status from all monitors
      if (safetyMonitors.isEmpty) {
        return Response.ok(
          jsonEncode({
            "isSafe": true, // Fail-open: assume safe if no monitors connected
            "monitorsConnected": 0,
            "monitors": <Map<String, dynamic>>[],
            "message": "No safety monitors connected - assuming safe (fail-open mode)",
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // TODO: Query each monitor for actual status
      final monitorStatuses = safetyMonitors.map((m) => {
        'deviceId': m.id,
        'deviceName': m.name,
        'isSafe': true, // Placeholder
        'unsafeReasons': <String>[],
      }).toList();

      // Aggregate: all monitors must report safe
      final allSafe = monitorStatuses.every((m) => m['isSafe'] == true);
      final allReasons = monitorStatuses
          .expand((m) => m['unsafeReasons'] as List<String>)
          .toList();

      return Response.ok(
        jsonEncode({
          "isSafe": allSafe,
          "monitorsConnected": safetyMonitors.length,
          "monitors": monitorStatuses,
          "unsafeReasons": allReasons,
          "lastUpdate": DateTime.now().toIso8601String(),
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Safety status error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Safety Settings
  // ===========================================================================

  /// GET /api/safety/settings
  /// Gets safety-related settings.
  Future<Response> handleGetSafetySettings(Request request) async {
    try {
      // TODO: Load settings from database/preferences when implemented
      return Response.ok(
        jsonEncode({
          "failMode": "fail_open", // fail_open, fail_closed, warn_only
          "checkIntervalSeconds": 30,
          "autoStopOnUnsafe": true,
          "autoParkOnUnsafe": true,
          "autoCloseRoofOnUnsafe": true,
          "warningDelaySeconds": 60, // Time to wait before taking action
          "requiredSafeDurationSeconds": 300, // Must be safe for this long to resume
          "enabledMonitors": <String>[], // List of device IDs to consider
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Get safety settings error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  /// POST /api/safety/settings
  /// Updates safety-related settings.
  /// Request body: { "failMode": "fail_closed", "checkIntervalSeconds": 60, ... }
  Future<Response> handleUpdateSafetySettings(Request request) async {
    print('[API] POST /api/safety/settings');
    try {
      final payload = jsonDecode(await request.readAsString());

      // Validate fail mode if provided
      final failMode = payload['failMode'] as String?;
      if (failMode != null) {
        final validModes = ['fail_open', 'fail_closed', 'warn_only'];
        if (!validModes.contains(failMode)) {
          return Response.badRequest(
            body: jsonEncode({
              "error": "Invalid failMode. Must be one of: ${validModes.join(', ')}"
            }),
            headers: {'content-type': 'application/json'},
          );
        }
      }

      // Validate check interval if provided
      final checkInterval = payload['checkIntervalSeconds'] as int?;
      if (checkInterval != null && checkInterval < 5) {
        return Response.badRequest(
          body: jsonEncode({
            "error": "checkIntervalSeconds must be at least 5 seconds"
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // TODO: Save settings to database/preferences when implemented

      return Response.ok(
        jsonEncode({
          "status": "ok",
          "message": "Safety settings updated",
          "settings": {
            "failMode": payload['failMode'] ?? "fail_open",
            "checkIntervalSeconds": payload['checkIntervalSeconds'] ?? 30,
            "autoStopOnUnsafe": payload['autoStopOnUnsafe'] ?? true,
            "autoParkOnUnsafe": payload['autoParkOnUnsafe'] ?? true,
            "autoCloseRoofOnUnsafe": payload['autoCloseRoofOnUnsafe'] ?? true,
            "warningDelaySeconds": payload['warningDelaySeconds'] ?? 60,
            "requiredSafeDurationSeconds": payload['requiredSafeDurationSeconds'] ?? 300,
            "enabledMonitors": payload['enabledMonitors'] ?? <String>[],
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Update safety settings error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Safety Acknowledgement
  // ===========================================================================

  /// POST /api/safety/acknowledge
  /// Acknowledges an unsafe condition, allowing operations to continue despite the warning.
  /// This is typically used when the operator has manually verified conditions are acceptable.
  /// Request body: { "deviceId": "safety_monitor_id", "reason": "Manually verified conditions" }
  Future<Response> handleAcknowledgeUnsafe(Request request) async {
    print('[API] POST /api/safety/acknowledge');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String?;
      final reason = payload['reason'] as String?;
      final durationMinutes = payload['durationMinutes'] as int? ?? 60;

      if (reason == null || reason.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({"error": "reason is required to acknowledge unsafe condition"}),
          headers: {'content-type': 'application/json'},
        );
      }

      // Calculate acknowledgement expiration
      final expiresAt = DateTime.now().add(Duration(minutes: durationMinutes));

      // TODO: Store acknowledgement in state/database when implemented

      return Response.ok(
        jsonEncode({
          "status": "acknowledged",
          "deviceId": deviceId,
          "reason": reason,
          "acknowledgedAt": DateTime.now().toIso8601String(),
          "expiresAt": expiresAt.toIso8601String(),
          "durationMinutes": durationMinutes,
          "message": "Unsafe condition acknowledged. Will auto-expire in $durationMinutes minutes.",
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Safety acknowledge error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }
}
