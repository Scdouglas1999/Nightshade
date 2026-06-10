/// Declarative route table for the framing-and-centering surface.
///
/// Counterpart to `handlers/framing_handlers.dart`. Wraps slew-to-
/// target, center-on-target (plate-solve loop), and rotator align
/// flows; mirrors a subset of the device routes but with the framing
/// service's higher-level orchestration on top.
library;

import '../handlers/framing_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [FramingHandlers].
List<HeadlessRoute> buildFramingRoutes(FramingHandlers h) => <HeadlessRoute>[
  HeadlessRoute(
    HttpMethod.post,
    '/api/framing/slew-to-target',
    h.handleSlewToTarget,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/framing/center-on-target',
    h.handleCenterOnTarget,
  ),
  HeadlessRoute(HttpMethod.post, '/api/framing/sync', h.handleSyncMount),
  HeadlessRoute(
    HttpMethod.get,
    '/api/framing/current-position',
    h.handleGetCurrentPosition,
  ),
  HeadlessRoute(HttpMethod.post, '/api/framing/rotate-to', h.handleRotateTo),
  HeadlessRoute(HttpMethod.post, '/api/framing/abort-slew', h.handleAbortSlew),
  HeadlessRoute(HttpMethod.post, '/api/framing/park', h.handleParkMount),
  HeadlessRoute(HttpMethod.post, '/api/framing/unpark', h.handleUnparkMount),
  HeadlessRoute(HttpMethod.post, '/api/framing/set-target', h.handleSetTarget),
  HeadlessRoute(HttpMethod.post, '/api/framing/save', h.handleSaveFraming),
];
