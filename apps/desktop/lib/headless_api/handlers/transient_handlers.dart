import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

/// Handlers for transient astronomical event alerts
class TransientHandlers {
  final ProviderContainer container;

  /// Track dismissed alert IDs (persists for session)
  final Set<String> _dismissedAlertIds = {};

  /// Track queued alert IDs (persists for session)
  final Set<String> _queuedAlertIds = {};

  TransientHandlers(this.container);

  // ===========================================================================
  // Get Active Transients
  // ===========================================================================

  Future<Response> handleGetActiveTransients(Request request) async {
    print('[API] GET /api/transients');
    try {
      final service = container.read(transientAlertServiceProvider);

      // Use default settings (can be enhanced with database storage later)
      final settings = _getDefaultSettings();

      // Fetch alerts from configured sources
      final alerts = await service.getAllAlerts(settings);

      // Filter out dismissed alerts
      final activeAlerts = alerts.where((a) => !_dismissedAlertIds.contains(a.id)).toList();

      return Response.ok(
        jsonEncode({
          "alerts": activeAlerts.map((a) => _alertToJson(a)).toList(),
          "totalCount": alerts.length,
          "dismissedCount": _dismissedAlertIds.length,
          "queuedCount": _queuedAlertIds.length,
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Get transients error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Get Transient Settings
  // ===========================================================================

  Future<Response> handleGetSettings(Request request) async {
    print('[API] GET /api/transients/settings');
    try {
      // Return current in-memory settings
      final settings = _getDefaultSettings();

      return Response.ok(
        jsonEncode({
          "settings": {
            "enabledSources": settings.enabledSources.map((s) => s.name).toList(),
            "typesToMonitor": settings.typesToMonitor.map((t) => t.name).toList(),
            "magnitudeThreshold": settings.magnitudeThreshold,
            "notifyOnNew": settings.notifyOnNew,
            "autoQueueBright": settings.autoQueueBright,
            "autoQueueMagnitude": settings.autoQueueMagnitude,
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Get transient settings error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Update Transient Settings
  // ===========================================================================

  Future<Response> handleUpdateSettings(Request request) async {
    print('[API] POST /api/transients/settings');
    try {
      // Settings update is a no-op for now since we don't have persistent storage
      // In the future, this could be stored in app settings as JSON
      return Response.ok(
        jsonEncode({
          "status": "acknowledged",
          "message": "Transient settings are not persisted in this version",
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Update transient settings error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Queue Transient For Observation
  // ===========================================================================

  Future<Response> handleQueueTransient(Request request, String id) async {
    print('[API] POST /api/transients/$id/queue');
    try {
      _queuedAlertIds.add(id);

      return Response.ok(
        jsonEncode({
          "status": "queued",
          "alertId": id,
          "queuedCount": _queuedAlertIds.length,
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Queue transient error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Dismiss Transient
  // ===========================================================================

  Future<Response> handleDismissTransient(Request request, String id) async {
    print('[API] POST /api/transients/$id/dismiss');
    try {
      _dismissedAlertIds.add(id);

      return Response.ok(
        jsonEncode({
          "status": "dismissed",
          "alertId": id,
          "dismissedCount": _dismissedAlertIds.length,
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Dismiss transient error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Refresh Alerts (Clear Cache)
  // ===========================================================================

  Future<Response> handleRefreshAlerts(Request request) async {
    print('[API] POST /api/transients/refresh');
    try {
      final service = container.read(transientAlertServiceProvider);
      service.clearCache();

      return Response.ok(
        jsonEncode({"status": "cache_cleared"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Refresh alerts error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Get Queued Transients
  // ===========================================================================

  Future<Response> handleGetQueued(Request request) async {
    print('[API] GET /api/transients/queued');
    try {
      final service = container.read(transientAlertServiceProvider);

      // Use default settings
      final settings = _getDefaultSettings();

      // Fetch all alerts and filter to queued ones
      final alerts = await service.getAllAlerts(settings);
      final queuedAlerts = alerts.where((a) => _queuedAlertIds.contains(a.id)).toList();

      return Response.ok(
        jsonEncode({
          "queued": queuedAlerts.map((a) => _alertToJson(a)).toList(),
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Get queued error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  TransientAlertSettings _getDefaultSettings() {
    return const TransientAlertSettings(
      enabledSources: {TransientSource.aavso},
      typesToMonitor: {TransientType.supernova, TransientType.nova},
      magnitudeThreshold: 14.0,
      notifyOnNew: true,
      autoQueueBright: false,
      autoQueueMagnitude: 10.0,
    );
  }

  Map<String, dynamic> _alertToJson(TransientAlert alert) {
    return {
      'id': alert.id,
      'name': alert.name,
      'type': alert.type.name,
      'raHours': alert.raHours,
      'decDegrees': alert.decDegrees,
      'magnitude': alert.magnitude,
      'peakMagnitude': alert.peakMagnitude,
      'discoveryTime': alert.discoveryTime.millisecondsSinceEpoch,
      'lastUpdated': alert.lastUpdated.millisecondsSinceEpoch,
      'source': alert.source.name,
      'sourceUrl': alert.sourceUrl,
      'priority': alert.priority,
      'classification': alert.classification,
      'isQueued': _queuedAlertIds.contains(alert.id),
      'isDismissed': _dismissedAlertIds.contains(alert.id),
    };
  }
}
