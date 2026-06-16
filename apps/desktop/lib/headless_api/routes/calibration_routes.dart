/// Declarative route table for the calibration-library surface
/// (darks, flats, defect maps).
///
/// Counterpart to `handlers/calibration_handlers.dart`. Previously the
/// only way to manage these tables on a headless Pi was SSH; now they
/// have a full REST surface. Order constraint inside each sub-prefix:
/// the literal sub-paths (`upload`, `find-match`, `backfill-sizes`,
/// `recommendation`) MUST register before the `<id>`-parameterised
/// route on the same prefix.
library;

import '../handlers/calibration_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [CalibrationHandlers].
List<HeadlessRoute> buildCalibrationRoutes(
  CalibrationHandlers h,
) => <HeadlessRoute>[
  // Remote dark-library auto-match for frame calibration. A remote client
  // can't run the matcher locally (the library lives on the host), so it
  // posts the light frame's capture params here and gets back the matched
  // dark's on-host path (or null) to feed to /api/imaging/calibrate-file.
  HeadlessRoute(
    HttpMethod.post,
    '/api/calibration/match-dark',
    h.handleMatchDark,
  ),

  // Darks
  HeadlessRoute(HttpMethod.get, '/api/calibration/darks', h.handleListDarks),
  HeadlessRoute(
    HttpMethod.post,
    '/api/calibration/darks',
    h.handleRegisterDark,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/calibration/darks/upload',
    h.handleUploadDark,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/calibration/darks/find-match',
    h.handleFindMatchingDark,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/calibration/darks/backfill-sizes',
    h.handleVerifyDarkSizes,
  ),
  HeadlessRoute(HttpMethod.get, '/api/calibration/darks/<id>', h.handleGetDark),
  HeadlessRoute(
    HttpMethod.get,
    '/api/calibration/darks/<id>/download',
    h.handleDownloadDark,
  ),
  HeadlessRoute(
    HttpMethod.delete,
    '/api/calibration/darks/<id>',
    h.handleDeleteDark,
  ),

  // Flats
  HeadlessRoute(HttpMethod.get, '/api/calibration/flats', h.handleListFlats),
  HeadlessRoute(HttpMethod.post, '/api/calibration/flats', h.handleRecordFlat),
  HeadlessRoute(
    HttpMethod.get,
    '/api/calibration/flats/recommendation',
    h.handleFlatRecommendation,
  ),
  HeadlessRoute(HttpMethod.get, '/api/calibration/flats/<id>', h.handleGetFlat),
  HeadlessRoute(
    HttpMethod.delete,
    '/api/calibration/flats/<id>',
    h.handleDeleteFlat,
  ),

  // Defect maps
  HeadlessRoute(
    HttpMethod.get,
    '/api/calibration/defect-maps',
    h.handleListDefectMaps,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/calibration/defect-maps',
    h.handleRegisterDefectMap,
  ),
  // Literal sub-paths MUST register before the `<id>` route below.
  HeadlessRoute(
    HttpMethod.post,
    '/api/calibration/defect-maps/build',
    h.handleBuildDefectMap,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/calibration/defect-maps/apply',
    h.handleApplyDefectMap,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/calibration/defect-maps/<id>',
    h.handleGetDefectMap,
  ),
  HeadlessRoute(
    HttpMethod.delete,
    '/api/calibration/defect-maps/<id>',
    h.handleDeleteDefectMap,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/calibration/defect-maps/<id>/regenerate',
    h.handleRegenerateDefectMap,
  ),
];
