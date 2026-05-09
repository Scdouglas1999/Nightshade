import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';

/// Handlers for safety monitor endpoints
///
/// Safety monitors report whether it is safe to continue observing based on
/// various conditions like weather, power status, or custom sensor inputs.
/// Multiple safety monitors can be connected, and all must report "safe"
/// for the system to consider conditions safe for imaging.
class SafetyMonitorHandlers {
  final ProviderContainer container;

  SafetyMonitorHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'SafetyMonitorHandlers');
  void _logError(String message) =>
      _logger.error(message, source: 'SafetyMonitorHandlers');

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
      final safetyMonitors = connectedDevices
          .where(
            (d) => d.deviceType == DeviceType.safetyMonitor,
          )
          .toList();

      // Read the real safety monitor device state from the provider
      final safetyMonitorState = container.read(safetyMonitorStateProvider);

      if (deviceId != null && deviceId.isNotEmpty) {
        // Return status for specific device
        final monitor = safetyMonitors.firstWhere(
          (d) => d.id == deviceId,
          orElse: () => const DeviceInfo(
            id: '',
            name: '',
            deviceType: DeviceType.safetyMonitor,
            driverType: DriverType.simulator,
            description: '',
            driverVersion: '',
          ),
        );

        if (monitor.id.isEmpty) {
          return jsonResponse(
            {
              "connected": false,
              "deviceId": deviceId,
              "error":
                  "Safety monitor '$deviceId' not connected - cannot determine safety state",
            },
            statusCode: 503,
          );
        }

        // Use real safety state from the connected device
        final isDeviceMatch = safetyMonitorState.deviceId == deviceId;
        final isConnected = isDeviceMatch &&
            safetyMonitorState.connectionState ==
                DeviceConnectionState.connected;

        if (!isConnected) {
          return jsonResponse(
            {
              "connected": false,
              "deviceId": deviceId,
              "error":
                  "Safety monitor '$deviceId' found but not in connected state - cannot determine safety state",
            },
            statusCode: 503,
          );
        }

        return jsonOk(
          {
            "connected": true,
            "deviceId": deviceId,
            "deviceName": monitor.name,
            "isSafe": safetyMonitorState.isSafe,
            "lastChecked": safetyMonitorState.lastChecked?.toIso8601String(),
            "lastUpdate": DateTime.now().toIso8601String(),
          },
        );
      }

      // Return aggregate status from all monitors using the weather safety provider
      // which already combines all safety sources (API weather, hardware weather, safety monitors)
      final weatherSafety = container.read(weatherSafetyProvider);

      if (safetyMonitors.isEmpty) {
        // No safety monitors connected - use aggregate weather safety state
        // but report accurately that no monitors are connected
        return jsonOk(
          {
            "isSafe": weatherSafety.isSafe,
            "monitorsConnected": 0,
            "monitors": <Map<String, dynamic>>[],
            "dataSource": weatherSafety.dataSource.name,
            "safetyStatus": weatherSafety.status.name,
            "failModeWarning": weatherSafety.failModeWarning,
            "lastEvaluation": weatherSafety.lastEvaluation?.toIso8601String(),
          },
        );
      }

      // Build per-monitor status using real device state
      final monitorStatuses = safetyMonitors.map((m) {
        final isThisDevice = safetyMonitorState.deviceId == m.id;
        final isConnected = isThisDevice &&
            safetyMonitorState.connectionState ==
                DeviceConnectionState.connected;

        return {
          'deviceId': m.id,
          'deviceName': m.name,
          'connected': isConnected,
          'isSafe': isConnected ? safetyMonitorState.isSafe : null,
          'lastChecked': isConnected
              ? safetyMonitorState.lastChecked?.toIso8601String()
              : null,
        };
      }).toList();

      return jsonOk(
        {
          "isSafe": weatherSafety.isSafe,
          "safetyStatus": weatherSafety.status.name,
          "monitorsConnected": safetyMonitors.length,
          "monitors": monitorStatuses,
          "dataSource": weatherSafety.dataSource.name,
          "hardwareWeatherSafe": weatherSafety.hardwareWeatherSafe,
          "safetyMonitorSafe": weatherSafety.safetyMonitorSafe,
          "apiWeatherSafe": weatherSafety.apiWeatherSafe,
          "failModeWarning": weatherSafety.failModeWarning,
          "lastEvaluation": weatherSafety.lastEvaluation?.toIso8601String(),
          "lastUpdate": DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      _logError('Safety status error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Safety Settings
  // ===========================================================================

  /// GET /api/safety/settings
  /// Gets safety-related settings.
  Future<Response> handleGetSafetySettings(Request request) async {
    try {
      return jsonOk(
        {
          "failMode": "fail_closed", // fail_open, fail_closed, warn_only
          "checkIntervalSeconds": 30,
          "autoStopOnUnsafe": true,
          "autoParkOnUnsafe": true,
          "autoCloseRoofOnUnsafe": true,
          "warningDelaySeconds": 60, // Time to wait before taking action
          "requiredSafeDurationSeconds":
              300, // Must be safe for this long to resume
          "enabledMonitors": <String>[], // List of device IDs to consider
        },
      );
    } catch (e) {
      _logError('Get safety settings error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  /// POST /api/safety/settings
  /// Updates safety-related settings.
  /// Request body: { "failMode": "fail_closed", "checkIntervalSeconds": 60, ... }
  Future<Response> handleUpdateSafetySettings(Request request) async {
    _logInfo('POST /api/safety/settings');
    try {
      final payload = jsonDecode(await request.readAsString());

      // Validate fail mode if provided
      final failMode = payload['failMode'] as String?;
      if (failMode != null) {
        final validModes = ['fail_open', 'fail_closed', 'warn_only'];
        if (!validModes.contains(failMode)) {
          return jsonBadRequest({
            "error":
                "Invalid failMode. Must be one of: ${validModes.join(', ')}"
          });
        }
      }

      // Validate check interval if provided
      final checkInterval = payload['checkIntervalSeconds'] as int?;
      if (checkInterval != null && checkInterval < 5) {
        return jsonBadRequest(
          {"error": "checkIntervalSeconds must be at least 5 seconds"},
        );
      }

      // Settings persistence is not yet implemented - return 501 rather than
      // pretending the update succeeded while discarding the data.
      _logError(
          'POST /api/safety/settings called but settings persistence is not yet implemented');
      return jsonNotImplemented({
        "error":
            "Safety settings persistence not yet implemented - settings were validated but cannot be saved",
        "receivedPayload": payload,
      });
    } catch (e) {
      _logError('Update safety settings error: $e');
      return jsonInternalServerError({"error": e.toString()});
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
    _logInfo('POST /api/safety/acknowledge');
    try {
      final payload = jsonDecode(await request.readAsString());
      final reason = payload['reason'] as String?;

      if (reason == null || reason.isEmpty) {
        return jsonBadRequest(
          {"error": "reason is required to acknowledge unsafe condition"},
        );
      }

      // Acknowledgement persistence is not yet implemented - return 501 rather
      // than pretending the acknowledgement was stored while discarding it.
      _logError(
          'POST /api/safety/acknowledge called but acknowledgement persistence is not yet implemented');
      return jsonNotImplemented({
        "error":
            "Safety acknowledgement persistence not yet implemented - acknowledgement was validated but cannot be stored",
      });
    } catch (e) {
      _logError('Safety acknowledge error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }
}
