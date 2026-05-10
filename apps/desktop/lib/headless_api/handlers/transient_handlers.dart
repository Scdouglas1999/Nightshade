import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';
import '../validation.dart';

/// Handlers for transient astronomical event alerts
class TransientHandlers {
  final ProviderContainer container;

  /// Track dismissed alert IDs (persists for session)
  final Set<String> _dismissedAlertIds = {};

  /// Track queued alert IDs (persists for session)
  final Set<String> _queuedAlertIds = {};

  TransientAlertSettings _settings = const TransientAlertSettings(
    enabledSources: {TransientSource.aavso},
    typesToMonitor: {TransientType.supernova, TransientType.nova},
    magnitudeThreshold: 14.0,
    notifyOnNew: true,
    autoQueueBright: false,
    autoQueueMagnitude: 10.0,
  );

  TransientHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'TransientHandlers');

  // ===========================================================================
  // Get Active Transients
  // ===========================================================================

  Future<Response> handleGetActiveTransients(Request request) async {
    _logInfo('[API] GET /api/transients');
    final service = container.read(transientAlertServiceProvider);

    final settings = _settings;

    // Fetch alerts from configured sources
    final alerts = await service.getAllAlerts(settings);

    // Filter out dismissed alerts
    final activeAlerts =
        alerts.where((a) => !_dismissedAlertIds.contains(a.id)).toList();

    return jsonOk({
      "alerts": activeAlerts.map((a) => _alertToJson(a)).toList(),
      "totalCount": alerts.length,
      "dismissedCount": _dismissedAlertIds.length,
      "queuedCount": _queuedAlertIds.length,
    });
  }

  // ===========================================================================
  // Get Transient Settings
  // ===========================================================================

  Future<Response> handleGetSettings(Request request) async {
    _logInfo('[API] GET /api/transients/settings');
    final settings = _settings;

    return jsonOk({
      "settings": {
        "enabledSources": settings.enabledSources.map((s) => s.name).toList(),
        "typesToMonitor": settings.typesToMonitor.map((t) => t.name).toList(),
        "magnitudeThreshold": settings.magnitudeThreshold,
        "notifyOnNew": settings.notifyOnNew,
        "autoQueueBright": settings.autoQueueBright,
        "autoQueueMagnitude": settings.autoQueueMagnitude,
      },
    });
  }

  // ===========================================================================
  // Update Transient Settings
  // ===========================================================================

  Future<Response> handleUpdateSettings(Request request) async {
    _logInfo('[API] POST /api/transients/settings');
    final payload = await readJsonObject(request);

    // Why: enabledSources / typesToMonitor are accepted as either an array
    // (replacement) or omitted entirely (keep existing). Unknown enum names
    // are filtered silently — that mirrors the historical behaviour and is
    // safer than 400-ing on a single unrecognised source name.
    Set<TransientSource> enabledSources = _settings.enabledSources;
    final rawSources = optionalList<String>(payload, 'enabledSources');
    if (rawSources != null) {
      enabledSources =
          rawSources.map(_parseSource).whereType<TransientSource>().toSet();
    }

    Set<TransientType> typesToMonitor = _settings.typesToMonitor;
    final rawTypes = optionalList<String>(payload, 'typesToMonitor');
    if (rawTypes != null) {
      typesToMonitor =
          rawTypes.map(_parseType).whereType<TransientType>().toSet();
    }

    final magnitudeThreshold = optionalDouble(payload, 'magnitudeThreshold') ??
        _settings.magnitudeThreshold;
    final autoQueueMagnitude = optionalDouble(payload, 'autoQueueMagnitude') ??
        _settings.autoQueueMagnitude;
    final notifyOnNew =
        optionalBool(payload, 'notifyOnNew') ?? _settings.notifyOnNew;
    final autoQueueBright =
        optionalBool(payload, 'autoQueueBright') ?? _settings.autoQueueBright;

    _settings = TransientAlertSettings(
      enabledSources: enabledSources,
      typesToMonitor: typesToMonitor,
      magnitudeThreshold: magnitudeThreshold,
      notifyOnNew: notifyOnNew,
      autoQueueBright: autoQueueBright,
      autoQueueMagnitude: autoQueueMagnitude,
    );

    return jsonOk({
      "status": "ok",
      "settings": {
        "enabledSources":
            _settings.enabledSources.map((s) => s.name).toList(),
        "typesToMonitor":
            _settings.typesToMonitor.map((t) => t.name).toList(),
        "magnitudeThreshold": _settings.magnitudeThreshold,
        "notifyOnNew": _settings.notifyOnNew,
        "autoQueueBright": _settings.autoQueueBright,
        "autoQueueMagnitude": _settings.autoQueueMagnitude,
      },
    });
  }

  // ===========================================================================
  // Queue Transient For Observation
  // ===========================================================================

  Future<Response> handleQueueTransient(Request request, String id) async {
    _logInfo('[API] POST /api/transients/$id/queue');
    _queuedAlertIds.add(id);

    return jsonOk({
      "status": "queued",
      "alertId": id,
      "queuedCount": _queuedAlertIds.length,
    });
  }

  // ===========================================================================
  // Dismiss Transient
  // ===========================================================================

  Future<Response> handleDismissTransient(Request request, String id) async {
    _logInfo('[API] POST /api/transients/$id/dismiss');
    _dismissedAlertIds.add(id);

    return jsonOk({
      "status": "dismissed",
      "alertId": id,
      "dismissedCount": _dismissedAlertIds.length,
    });
  }

  // ===========================================================================
  // Refresh Alerts (Clear Cache)
  // ===========================================================================

  Future<Response> handleRefreshAlerts(Request request) async {
    _logInfo('[API] POST /api/transients/refresh');
    final service = container.read(transientAlertServiceProvider);
    service.clearCache();

    return jsonOk({"status": "cache_cleared"});
  }

  // ===========================================================================
  // Get Queued Transients
  // ===========================================================================

  Future<Response> handleGetQueued(Request request) async {
    _logInfo('[API] GET /api/transients/queued');
    final service = container.read(transientAlertServiceProvider);

    final settings = _settings;

    // Fetch all alerts and filter to queued ones
    final alerts = await service.getAllAlerts(settings);
    final queuedAlerts =
        alerts.where((a) => _queuedAlertIds.contains(a.id)).toList();

    return jsonOk({
      "queued": queuedAlerts.map((a) => _alertToJson(a)).toList(),
    });
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  TransientSource? _parseSource(String value) {
    final normalized = value.trim().toLowerCase();
    for (final source in TransientSource.values) {
      if (source.name.toLowerCase() == normalized) return source;
    }
    return null;
  }

  TransientType? _parseType(String value) {
    final normalized = value.trim().toLowerCase();
    for (final type in TransientType.values) {
      if (type.name.toLowerCase() == normalized) return type;
    }
    return null;
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
