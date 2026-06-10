/// Declarative route table for the unified Calibration Library Manager
/// (browse / auto-match / tag) over darks, flats, biases, and defect maps.
///
/// Counterpart to `handlers/calibration_library_handlers.dart`. Distinct
/// prefix (`/api/calibration-library`) from the P1-10 per-table CRUD surface
/// (`/api/calibration/*`): this is the library *view* + transparent matcher.
/// Order constraint: the literal `match` sub-path MUST register before the
/// `<type>/<id>` parameterised routes on the same prefix.
library;

import '../handlers/calibration_library_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [CalibrationLibraryHandlers].
List<HeadlessRoute> buildCalibrationLibraryRoutes(
  CalibrationLibraryHandlers h,
) => <HeadlessRoute>[
  HeadlessRoute(HttpMethod.get, '/api/calibration-library', h.handleList),
  HeadlessRoute(
    HttpMethod.post,
    '/api/calibration-library/match',
    h.handleMatch,
  ),
  HeadlessRoute(
    HttpMethod.put,
    '/api/calibration-library/<type>/<id>/tags',
    h.handleSetTags,
  ),
  HeadlessRoute(
    HttpMethod.delete,
    '/api/calibration-library/<type>/<id>',
    h.handleDelete,
  ),
];
