/// Declarative route table for safety-monitor endpoints.
///
/// Counterpart to `handlers/safety_monitor_handlers.dart`. The
/// settings/acknowledge POSTs sit at the default control rate limit
/// per `route_metadata.dart`; `_status` and `_settings` GETs are read-
/// only and uncapped.
library;

import '../handlers/safety_monitor_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [SafetyMonitorHandlers].
List<HeadlessRoute> buildSafetyMonitorRoutes(SafetyMonitorHandlers h) =>
    <HeadlessRoute>[
      HeadlessRoute(HttpMethod.get, '/api/safety/status', h.handleSafetyStatus),
      HeadlessRoute(
        HttpMethod.get,
        '/api/safety/settings',
        h.handleGetSafetySettings,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/safety/settings',
        h.handleUpdateSafetySettings,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/safety/acknowledge',
        h.handleAcknowledgeUnsafe,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/safety/cancel-acknowledgement',
        h.handleCancelAcknowledgement,
      ),
    ];
