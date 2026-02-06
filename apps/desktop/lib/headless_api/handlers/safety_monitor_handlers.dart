import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge;
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

/// Handlers for safety monitor endpoints.
class SafetyMonitorHandlers {
  final ProviderContainer container;

  final Map<String, dynamic> _settings = {
    'failMode': 'fail_open',
    'checkIntervalSeconds': 30,
    'autoStopOnUnsafe': true,
    'autoParkOnUnsafe': true,
    'autoCloseRoofOnUnsafe': true,
    'warningDelaySeconds': 60,
    'requiredSafeDurationSeconds': 300,
    'enabledMonitors': <String>[],
  };

  final Map<String, DateTime> _acknowledgedUntilByDevice = {};

  SafetyMonitorHandlers(this.container);

  Response _json(Object body, {int statusCode = 200}) {
    return Response(
      statusCode,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<List<DeviceInfo>> _connectedSafetyMonitors() async {
    final backend = container.read(backendProvider);
    final connectedDevices = await backend.getConnectedDevices();
    return connectedDevices
        .where((d) => d.deviceType == DeviceType.safetyMonitor)
        .toList();
  }

  Map<String, dynamic> _monitorStatusJson({
    required String deviceId,
    required String deviceName,
    required bool isSafe,
    String? reason,
  }) {
    final now = DateTime.now();
    final acknowledgedUntil = _acknowledgedUntilByDevice[deviceId];
    final ackActive =
        acknowledgedUntil != null && acknowledgedUntil.isAfter(now);
    final effectiveSafe = isSafe || ackActive;
    final reasons = <String>[];
    if (!isSafe && reason != null && reason.isNotEmpty) {
      reasons.add(reason);
    }
    if (!isSafe && ackActive) {
      reasons.add('Acknowledged until ${acknowledgedUntil.toIso8601String()}');
    }

    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'isSafe': effectiveSafe,
      'rawIsSafe': isSafe,
      'unsafeReasons': reasons,
      'acknowledged': ackActive,
      'acknowledgedUntil': acknowledgedUntil?.toIso8601String(),
      'lastUpdate': now.toIso8601String(),
    };
  }

  /// GET /api/safety/status
  Future<Response> handleSafetyStatus(Request request) async {
    try {
      final deviceId = request.url.queryParameters['deviceId'];
      final safetyMonitors = await _connectedSafetyMonitors();

      if (deviceId != null && deviceId.isNotEmpty) {
        final matching = safetyMonitors.where((d) => d.id == deviceId);
        if (matching.isEmpty) {
          return _json(
            {
              'connected': false,
              'deviceId': deviceId,
              'isSafe': false,
              'error': 'Safety monitor not connected',
            },
            statusCode: 404,
          );
        }

        final monitor = matching.first;
        final caps =
            await bridge.apiGetSafetyMonitorCapabilities(deviceId: monitor.id);
        final status = _monitorStatusJson(
          deviceId: monitor.id,
          deviceName: monitor.name,
          isSafe: caps.isSafe,
          reason: caps.safetyDescription,
        );
        return _json({
          'connected': true,
          ...status,
        });
      }

      if (safetyMonitors.isEmpty) {
        return _json({
          'isSafe': false,
          'monitorsConnected': 0,
          'monitors': <Map<String, dynamic>>[],
          'unsafeReasons': ['No safety monitors connected'],
          'lastUpdate': DateTime.now().toIso8601String(),
        });
      }

      final monitorStatuses = <Map<String, dynamic>>[];
      for (final monitor in safetyMonitors) {
        try {
          final caps = await bridge.apiGetSafetyMonitorCapabilities(
              deviceId: monitor.id);
          monitorStatuses.add(_monitorStatusJson(
            deviceId: monitor.id,
            deviceName: monitor.name,
            isSafe: caps.isSafe,
            reason: caps.safetyDescription,
          ));
        } catch (e) {
          monitorStatuses.add(_monitorStatusJson(
            deviceId: monitor.id,
            deviceName: monitor.name,
            isSafe: false,
            reason: 'Safety monitor query failed: $e',
          ));
        }
      }

      final allSafe = monitorStatuses.every((m) => m['isSafe'] == true);
      final allReasons = monitorStatuses
          .expand((m) => (m['unsafeReasons'] as List).cast<String>())
          .toList();

      return _json({
        'isSafe': allSafe,
        'monitorsConnected': safetyMonitors.length,
        'monitors': monitorStatuses,
        'unsafeReasons': allReasons,
        'lastUpdate': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      return _json({'error': e.toString()}, statusCode: 500);
    }
  }

  /// GET /api/safety/settings
  Future<Response> handleGetSafetySettings(Request request) async {
    return _json({'settings': _settings});
  }

  /// POST /api/safety/settings
  Future<Response> handleUpdateSafetySettings(Request request) async {
    try {
      final payload =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;

      final failMode = payload['failMode'] as String?;
      if (failMode != null) {
        const validModes = ['fail_open', 'fail_closed', 'warn_only'];
        if (!validModes.contains(failMode)) {
          return _json(
            {
              'error':
                  'Invalid failMode. Must be one of: ${validModes.join(', ')}'
            },
            statusCode: 400,
          );
        }
        _settings['failMode'] = failMode;
      }

      final checkInterval = payload['checkIntervalSeconds'] as int?;
      if (checkInterval != null) {
        if (checkInterval < 5) {
          return _json(
              {'error': 'checkIntervalSeconds must be at least 5 seconds'},
              statusCode: 400);
        }
        _settings['checkIntervalSeconds'] = checkInterval;
      }

      for (final key in const [
        'autoStopOnUnsafe',
        'autoParkOnUnsafe',
        'autoCloseRoofOnUnsafe',
      ]) {
        final value = payload[key];
        if (value is bool) {
          _settings[key] = value;
        }
      }

      for (final key in const [
        'warningDelaySeconds',
        'requiredSafeDurationSeconds'
      ]) {
        final value = payload[key];
        if (value is int && value >= 0) {
          _settings[key] = value;
        }
      }

      final monitors = payload['enabledMonitors'];
      if (monitors is List) {
        _settings['enabledMonitors'] = monitors.whereType<String>().toList();
      }

      return _json({'status': 'ok', 'settings': _settings});
    } catch (e) {
      return _json({'error': e.toString()}, statusCode: 500);
    }
  }

  /// POST /api/safety/acknowledge
  Future<Response> handleAcknowledgeUnsafe(Request request) async {
    try {
      final payload = jsonDecode(await request.readAsString());
      final reason = payload['reason'] as String?;
      final deviceId = payload['deviceId'] as String?;
      final durationMinutes = payload['durationMinutes'] as int? ?? 60;

      if (reason == null || reason.isEmpty) {
        return _json(
          {'error': 'reason is required to acknowledge unsafe condition'},
          statusCode: 400,
        );
      }
      if (durationMinutes <= 0) {
        return _json({'error': 'durationMinutes must be positive'},
            statusCode: 400);
      }

      final expiresAt = DateTime.now().add(Duration(minutes: durationMinutes));
      if (deviceId != null && deviceId.isNotEmpty) {
        _acknowledgedUntilByDevice[deviceId] = expiresAt;
      }

      return _json({
        'status': 'acknowledged',
        'deviceId': deviceId,
        'reason': reason,
        'acknowledgedAt': DateTime.now().toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'durationMinutes': durationMinutes,
      });
    } catch (e) {
      return _json({'error': e.toString()}, statusCode: 500);
    }
  }
}
