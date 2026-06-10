/// Declarative route table for read-only equipment status, capabilities,
/// and per-device heartbeat lifecycle.
///
/// Counterpart to `handlers/equipment_handlers.dart`. Mutating device
/// control verbs (slew, expose, change filter, etc.) live in
/// `device_routes.dart`; this surface is what the dashboard polls for
/// the equipment dock readout.
library;

import '../handlers/equipment_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [EquipmentHandlers].
List<HeadlessRoute> buildEquipmentRoutes(EquipmentHandlers h) =>
    <HeadlessRoute>[
      // Equipment Status
      HeadlessRoute(
        HttpMethod.get,
        '/api/equipment/camera/status',
        h.handleCameraStatus,
      ),
      HeadlessRoute(
        HttpMethod.get,
        '/api/equipment/mount/status',
        h.handleMountStatus,
      ),
      HeadlessRoute(
        HttpMethod.get,
        '/api/equipment/focuser/status',
        h.handleFocuserStatus,
      ),
      HeadlessRoute(
        HttpMethod.get,
        '/api/equipment/filter-wheel/status',
        h.handleFilterWheelStatus,
      ),
      HeadlessRoute(
        HttpMethod.get,
        '/api/equipment/rotator/status',
        h.handleRotatorStatus,
      ),

      // Equipment Capabilities
      HeadlessRoute(
        HttpMethod.get,
        '/api/equipment/camera/capabilities',
        h.handleCameraCapabilities,
      ),
      HeadlessRoute(
        HttpMethod.get,
        '/api/equipment/mount/capabilities',
        h.handleMountCapabilities,
      ),
      HeadlessRoute(
        HttpMethod.get,
        '/api/equipment/focuser/capabilities',
        h.handleFocuserCapabilities,
      ),
      HeadlessRoute(
        HttpMethod.get,
        '/api/equipment/filter-wheel/capabilities',
        h.handleFilterWheelCapabilities,
      ),
      HeadlessRoute(
        HttpMethod.get,
        '/api/equipment/rotator/capabilities',
        h.handleRotatorCapabilities,
      ),

      // Device Health
      HeadlessRoute(
        HttpMethod.post,
        '/api/device/heartbeat/start',
        h.handleStartDeviceHeartbeat,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/device/heartbeat/stop',
        h.handleStopDeviceHeartbeat,
      ),
      HeadlessRoute(
        HttpMethod.get,
        '/api/device/health/<deviceId>',
        h.handleGetDeviceHealth,
      ),
    ];
