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
