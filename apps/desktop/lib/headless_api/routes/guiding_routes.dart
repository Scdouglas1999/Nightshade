/// Declarative route table for autoguiding endpoints (PHD2, generic
/// guider, built-in guider config).
///
/// Counterpart to `handlers/guiding_handlers.dart`. The `/api/phd2/*`
/// subset is the legacy direct-PHD2 surface; `/api/guider/*` is the
/// vendor-neutral wrapper that delegates to whichever guider is
/// currently selected.
library;

import '../handlers/guiding_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [GuidingHandlers].
List<HeadlessRoute> buildGuidingRoutes(GuidingHandlers h) => <HeadlessRoute>[
  // PHD2 Guiding
  HeadlessRoute(HttpMethod.get, '/api/phd2/running', h.handlePhd2IsRunning),
  HeadlessRoute(HttpMethod.post, '/api/phd2/connect', h.handlePhd2Connect),
  HeadlessRoute(
    HttpMethod.post,
    '/api/phd2/disconnect',
    h.handlePhd2Disconnect,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/phd2/start-guiding',
    h.handlePhd2StartGuiding,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/phd2/stop-guiding',
    h.handlePhd2StopGuiding,
  ),
  HeadlessRoute(HttpMethod.post, '/api/phd2/dither', h.handlePhd2Dither),
  HeadlessRoute(HttpMethod.get, '/api/phd2/status', h.handlePhd2GetStatus),
  HeadlessRoute(HttpMethod.post, '/api/phd2/pause', h.handlePhd2SetPaused),
  HeadlessRoute(
    HttpMethod.post,
    '/api/phd2/clear-calibration',
    h.handlePhd2ClearCalibration,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/phd2/flip-calibration',
    h.handlePhd2FlipCalibration,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/phd2/get-calibration-data',
    h.handlePhd2GetCalibrationData,
  ),
  HeadlessRoute(HttpMethod.post, '/api/phd2/find-star', h.handlePhd2FindStar),
  HeadlessRoute(
    HttpMethod.post,
    '/api/phd2/set-lock-position',
    h.handlePhd2SetLockPosition,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/phd2/lock-position',
    h.handlePhd2GetLockPosition,
  ),
  HeadlessRoute(HttpMethod.post, '/api/phd2/loop', h.handlePhd2Loop),
  HeadlessRoute(
    HttpMethod.post,
    '/api/phd2/deselect-star',
    h.handlePhd2DeselectStar,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/phd2/star-image',
    h.handlePhd2GetStarImage,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/phd2/algo-params',
    h.handlePhd2GetAlgoParamNames,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/phd2/algo-param',
    h.handlePhd2GetAlgoParam,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/phd2/algo-param',
    h.handlePhd2SetAlgoParam,
  ),

  // Generic guider control
  HeadlessRoute(
    HttpMethod.post,
    '/api/guider/start-guiding',
    h.handleGuiderStartGuiding,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/guider/stop-guiding',
    h.handleGuiderStopGuiding,
  ),
  HeadlessRoute(HttpMethod.post, '/api/guider/dither', h.handleGuiderDither),
  HeadlessRoute(HttpMethod.post, '/api/guider/loop', h.handleGuiderLoop),
  HeadlessRoute(
    HttpMethod.post,
    '/api/guider/find-star',
    h.handleGuiderFindStar,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/guider/set-lock-position',
    h.handleGuiderSetLockPosition,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/guider/lock-position',
    h.handleGuiderGetLockPosition,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/guider/deselect-star',
    h.handleGuiderDeselectStar,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/guider/star-image',
    h.handleGuiderGetStarImage,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/builtin-guider/config',
    h.handleBuiltinGuiderGetConfig,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/builtin-guider/config',
    h.handleBuiltinGuiderSetConfig,
  ),
];
