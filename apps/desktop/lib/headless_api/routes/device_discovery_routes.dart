/// Declarative route table for device-discovery endpoints.
///
/// Counterpart to `handlers/device_discovery_handlers.dart`. Distinct
/// from device-control endpoints in [DeviceHandlers]: discovery is
/// read-only across native, INDI, and Alpaca transports, while the
/// connect/disconnect/expose write surface lives in `device_routes.dart`.
library;

import '../handlers/device_discovery_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [DeviceDiscoveryHandlers].
List<HeadlessRoute> buildDeviceDiscoveryRoutes(
  DeviceDiscoveryHandlers h,
) => <HeadlessRoute>[
  HeadlessRoute(HttpMethod.get, '/api/devices', h.handleGetDevices),
  HeadlessRoute(
    HttpMethod.get,
    '/api/devices/discover-indi',
    h.handleDiscoverIndiAtAddress,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/devices/discover-alpaca',
    h.handleDiscoverAlpacaAtAddress,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/devices/connected',
    h.handleGetConnectedDevices,
  ),
  HeadlessRoute(HttpMethod.post, '/api/devices/rescan', h.handleRescanDevices),
];
