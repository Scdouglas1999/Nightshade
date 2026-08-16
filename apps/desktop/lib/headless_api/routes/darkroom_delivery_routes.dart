/// Declarative route table for the Darkroom peer-delivery surface.
///
/// Counterpart to `handlers/darkroom_delivery_handlers.dart`. Three routes: the
/// signed per-job manifest, the Range-served artifact bytes, and the desktop's
/// acknowledgement that a file landed.
///
/// Registration order matters here as everywhere in this table — shelf_router
/// matches in declaration order — but these three paths share no prefix with a
/// parameterised route declared elsewhere, so they may be registered as a
/// block.
library;

import '../handlers/darkroom_delivery_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [DarkroomDeliveryHandlers].
List<HeadlessRoute> buildDarkroomDeliveryRoutes(DarkroomDeliveryHandlers h) =>
    <HeadlessRoute>[
      HeadlessRoute(
        HttpMethod.get,
        '/api/darkroom/delivery/manifest/<jobId>',
        h.handleGetDeliveryManifest,
      ),
      HeadlessRoute(
        HttpMethod.get,
        '/api/darkroom/delivery/artifact/<jobId>/<artifactId>',
        h.handleDownloadDeliveryArtifact,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/darkroom/delivery/ack/<jobId>',
        h.handleAcknowledgeDelivery,
      ),
    ];
