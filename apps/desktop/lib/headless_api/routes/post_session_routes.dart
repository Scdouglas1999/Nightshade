/// Declarative route table for the post-session integration / finishing surface.
///
/// Counterpart to `handlers/post_session_handlers.dart`. Lets a remote tablet
/// drive the "review and integrate last night's data" workflow on the HOST:
/// integrate a session into a master, drizzle-integrate, analyze the night's
/// SNR curve, build a master flat, colour-calibrate, extract the background,
/// combine narrowband channels, and run the multi-night accumulating master.
///
/// Every op runs host-side on host file paths (no client pixel upload) and is
/// [JobManager]-backed: the POST returns `{jobId}` and the client polls
/// `/api/jobs/{id}`. Mosaic stitching is intentionally excluded (separate
/// surface).
library;

import '../handlers/post_session_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [PostSessionHandlers].
List<HeadlessRoute> buildPostSessionRoutes(PostSessionHandlers h) =>
    <HeadlessRoute>[
      HeadlessRoute(
        HttpMethod.post,
        '/api/post-session/integrate',
        h.handleIntegrateSession,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/post-session/drizzle',
        h.handleDrizzleIntegrate,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/post-session/analyze-night',
        h.handleAnalyzeNight,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/post-session/build-master-flat',
        h.handleBuildMasterFlat,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/post-session/color-calibrate',
        h.handleColorCalibrate,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/post-session/detect-stars',
        h.handleDetectStars,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/post-session/extract-background',
        h.handleExtractBackground,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/post-session/combine-channels',
        h.handleCombineChannels,
      ),
      HeadlessRoute(
        HttpMethod.post,
        '/api/post-session/master-accumulate',
        h.handleMasterAccumulate,
      ),
    ];
