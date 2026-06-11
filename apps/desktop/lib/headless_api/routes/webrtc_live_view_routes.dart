/// declarative route table for the WebRTC live-view
/// signalling surface. Mirrors the per-domain pattern used elsewhere
/// in `routes/`; the only oddity is the GET ICE-events route which is
/// SSE-streaming rather than JSON request/response.
library;

import '../handlers/webrtc_live_view_handlers.dart';
import 'headless_route.dart';

List<HeadlessRoute> buildWebRtcLiveViewRoutes(
  WebRtcLiveViewHandlers handlers,
) => <HeadlessRoute>[
  HeadlessRoute(
    HttpMethod.post,
    '/api/webrtc/live-view/offer',
    handlers.handleOffer,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/webrtc/live-view/ice/<sessionId>',
    handlers.handleIce,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/webrtc/live-view/ice/<sessionId>/events',
    handlers.handleIceEvents,
  ),
  HeadlessRoute(
    HttpMethod.delete,
    '/api/webrtc/live-view/<sessionId>',
    handlers.handleDelete,
  ),
];
