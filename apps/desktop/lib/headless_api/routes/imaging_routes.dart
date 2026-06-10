/// Declarative route table for image-processing endpoints.
///
/// Counterpart to `handlers/imaging_handlers.dart`. Combines plate
/// solving (which depends on the imaging pipeline for the source frame)
/// with stats / stretch / debayer / save-FITS / calibrate-file actions.
library;

import '../handlers/imaging_handlers.dart';
import 'headless_route.dart';

/// Build the declarative route table for [ImagingHandlers].
List<HeadlessRoute> buildImagingRoutes(ImagingHandlers h) => <HeadlessRoute>[
  // Plate Solving
  HeadlessRoute(HttpMethod.post, '/api/plate-solve', h.handlePlateSolve),

  // Plate Solver Setup (host-owned: detect/verify/config for the
  // settings page; remote clients route here so they operate on the
  // host's filesystem rather than their own).
  HeadlessRoute(
    HttpMethod.get,
    '/api/plate-solver/detect',
    h.handleDetectPlateSolvers,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/plate-solver/verify',
    h.handleVerifyPlateSolver,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/plate-solver/config',
    h.handleGetPlateSolverConfig,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/plate-solver/config',
    h.handleSetPlateSolverConfig,
  ),

  // Imaging
  HeadlessRoute(HttpMethod.post, '/api/imaging/stats', h.handleGetImageStats),
  HeadlessRoute(
    HttpMethod.post,
    '/api/imaging/stretch',
    h.handleAutoStretchImage,
  ),
  HeadlessRoute(
    HttpMethod.get,
    '/api/imaging/star-crops',
    h.handleGetStarCrops,
  ),
  HeadlessRoute(HttpMethod.post, '/api/imaging/debayer', h.handleDebayerImage),
  HeadlessRoute(
    HttpMethod.get,
    '/api/imaging/raw-data',
    h.handleGetLastRawImageData,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/imaging/save-fits',
    h.handleSaveFitsFile,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/imaging/save-fits-from-capture',
    h.handleSaveFitsFromLastCapture,
  ),
  HeadlessRoute(
    HttpMethod.post,
    '/api/imaging/calibrate-file',
    h.handleCalibrateImageFile,
  ),
  HeadlessRoute(
    HttpMethod.delete,
    '/api/imaging/device-image/<deviceId>',
    h.handleClearDeviceImage,
  ),
];
