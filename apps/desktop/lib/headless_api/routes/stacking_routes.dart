/// Declarative route table for the live-stacking control surface.
///
/// Counterpart to `handlers/stacking_handlers.dart`. Lets a remote tablet
/// configure, start/stop, reset, and poll a host-side live stack (EAA), with a
/// binary preview endpoint for the stacked u16 image. Capture frames are fed to
/// the stacker on the host (see StackingHandlers.onImageSaved), so a running
/// sequence stacks live even with no client attached.
library;

import '../handlers/stacking_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [StackingHandlers].
List<HeadlessRoute> buildStackingRoutes(StackingHandlers h) => <HeadlessRoute>[
  HeadlessRoute(HttpMethod.post, '/api/stacking/start', h.handleStart),
  HeadlessRoute(HttpMethod.post, '/api/stacking/add-frame', h.handleAddFrame),
  HeadlessRoute(HttpMethod.post, '/api/stacking/config', h.handleUpdateConfig),
  HeadlessRoute(HttpMethod.post, '/api/stacking/reset', h.handleReset),
  HeadlessRoute(HttpMethod.post, '/api/stacking/stop', h.handleStop),
  HeadlessRoute(HttpMethod.get, '/api/stacking/status', h.handleStatus),
  HeadlessRoute(HttpMethod.get, '/api/stacking/stats', h.handleStats),
  HeadlessRoute(HttpMethod.get, '/api/stacking/result', h.handleResult),
  HeadlessRoute(HttpMethod.get, '/api/stacking/preview', h.handlePreview),
];
