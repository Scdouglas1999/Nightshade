/// Declarative route table for the auxiliary-device surface (switches
/// and cover calibrators).
///
/// Counterpart to `handlers/auxiliary_handlers.dart`. Switch endpoints
/// cover ASCOM `ISwitchV2` interfaces; cover endpoints handle dust
/// covers and electroluminescent flat panels.
library;

import '../handlers/auxiliary_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [AuxiliaryHandlers].
List<HeadlessRoute> buildAuxiliaryRoutes(AuxiliaryHandlers h) =>
    <HeadlessRoute>[
      HeadlessRoute(
          HttpMethod.get, '/api/switch/status', h.handleSwitchStatus),
      HeadlessRoute(HttpMethod.post, '/api/switch/set', h.handleSwitchSet),
      HeadlessRoute(HttpMethod.get, '/api/cover/status', h.handleCoverStatus),
      HeadlessRoute(HttpMethod.post, '/api/cover/open', h.handleCoverOpen),
      HeadlessRoute(HttpMethod.post, '/api/cover/close', h.handleCoverClose),
      HeadlessRoute(
          HttpMethod.post, '/api/cover/brightness', h.handleCoverBrightness),
      HeadlessRoute(HttpMethod.post, '/api/cover/calibrator-on',
          h.handleCalibratorOn),
      HeadlessRoute(HttpMethod.post, '/api/cover/calibrator-off',
          h.handleCalibratorOff),
    ];
