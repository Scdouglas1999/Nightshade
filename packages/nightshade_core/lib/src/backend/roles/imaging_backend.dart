import 'dart:async';
import 'dart:typed_data';

import 'package:nightshade_bridge/nightshade_bridge.dart' show PlateSolveResult;

import '../../models/autofocus_progress.dart' show StarCrop;
import '../../models/backend/backend_types.dart';
import '../../models/imaging/imaging_models.dart' show CapturedImage;
import '../../models/plate_solver.dart'
    show PlateSolverDetection, PlateSolverInfo, PlateSolverPreference;

/// Role interface covering image-data operations.
///
/// What this role owns:
///   * Pixel-buffer transforms: stats, auto-stretch, debayer, star-crop
///     extraction, calibration.
///   * FITS write (raw buffer and "save from last capture" fast-path).
///   * Plate solving against a file (in this codebase plate-solve drives
///     centering, polar align, framing — all imaging consumers).
///   * Polar alignment workflows (start/stop TPPA and all-sky/Sharpcap),
///     which are imaging-loop driven (the camera + plate solver are the
///     core dependencies; mount control is just a follower).
///   * Session image enumeration, thumbnails, full-image download for
///     mobile clients.
///
/// What this role deliberately does NOT own:
///   * Capturing exposures — see [DeviceBackend.cameraStartExposure].
///   * Sequencer image grading / quality config — see [SequencerBackend].
///   * Profile / settings — see [ProfileSettingsBackend].
abstract class ImagingBackend {
  // =========================================================================
  // FITS Save
  // =========================================================================

  /// Save FITS file directly from the last captured image stored server-side.
  /// This eliminates raw pixel data transfer across FFI/network boundaries.
  /// More efficient than saveFitsFile for normal capture workflows.
  Future<void> saveFitsFromLastCapture({
    required String deviceId,
    required String filePath,
    required FitsWriteHeader headerData,
  });

  // =========================================================================
  // Plate Solving
  // =========================================================================

  /// Solve an image file
  Future<PlateSolveResult> plateSolve({
    required String imagePath,
    double? ra,
    double? dec,
    double? fovDegrees,
  });

  // =========================================================================
  // Plate Solver Setup
  // =========================================================================
  //
  // Detection / verification / config read+write run against the machine
  // that owns the plate-solver binaries and catalog — i.e. the host wired
  // to the rig. On a remote (phone) client these MUST be routed to the host
  // so the settings page probes the host filesystem and persists solver
  // config on the host, not on the phone. [FfiBackend] runs them locally
  // via the Rust `api_platesolve_*` bridge; [NetworkBackend] forwards them
  // to the host over HTTP.

  /// Probe disk for installed solvers + ASTAP catalog and return a snapshot
  /// the settings UI can render directly.
  Future<PlateSolverDetection> detectPlateSolvers();

  /// Run the given solver binary's `--help` to confirm the install is
  /// healthy, surfacing its version banner.
  Future<PlateSolverInfo> verifyPlateSolver(String executablePath);

  /// Load the persisted plate-solver UX configuration (paths + choice).
  Future<PlateSolverPreference> getPlateSolverConfig();

  /// Persist plate-solver UX configuration. Invalidates the solver-
  /// availability cache so subsequent solves re-probe with the new paths.
  Future<void> setPlateSolverConfig(PlateSolverPreference pref);

  // =========================================================================
  // Image Processing
  // =========================================================================

  /// Get star crops from the last captured image for autofocus UI
  Future<List<StarCrop>> getStarCropsFromLastImage(
    String deviceId, {
    int maxCrops = 5,
  });

  /// Calibrate a light frame file on the host filesystem using optional
  /// master dark/flat/bias paths (also host-local when remote).
  Future<void> calibrateImageFile({
    required String lightPath,
    String? darkPath,
    String? flatPath,
    String? biasPath,
    required String outputPath,
  });

  // =========================================================================
  // Polar Alignment
  // =========================================================================

  /// Start three-point polar alignment
  ///
  /// This captures 3 images at different mount rotations to calculate
  /// the polar alignment error, then enters adjustment mode where it
  /// continuously updates the error values.
  Future<void> startPolarAlignment({
    required double exposureTime,
    required double stepSize,
    required int binning,
    required bool isNorth,
    required bool manualRotation,
    required bool rotateEast,
    int? gain,
    int? offset,
    double? solveTimeout,
    bool? startFromCurrent,
    double? autoCompleteThreshold,
  });

  /// Stop the polar alignment process
  Future<void> stopPolarAlignment();

  /// Start all-sky (Sharpcap-style) polar alignment.
  ///
  /// Unlike TPPA, this routine works from any direction in the sky. It
  /// captures a single exposure, plate-solves it to anchor a baseline, then
  /// re-solves every `iterationCadenceSecs` to measure drift relative to
  /// that baseline. From the drift signature and the observer's geographic
  /// location it recovers the polar-axis azimuth and altitude error.
  ///
  /// Requires an external plate solver (ASTAP); throws if one is not
  /// installed.
  ///
  /// * `exposureTime` — exposure duration per frame, seconds.
  /// * `solveTimeout` — plate-solve timeout per frame, seconds.
  /// * `binning` — camera binning factor.
  /// * `isNorth` — northern hemisphere observer.
  /// * `acceptanceThresholdArcsec` — auto-complete when total error stays
  ///   below this for 3 seconds (default 30″).
  /// * `iterationCadenceSecs` — re-solve cadence (default 3s).
  /// * `gain`, `offset` — optional camera parameters.
  Future<void> startAllSkyPolarAlignment({
    required double exposureTime,
    required double solveTimeout,
    required int binning,
    required bool isNorth,
    required double acceptanceThresholdArcsec,
    required double iterationCadenceSecs,
    int? gain,
    int? offset,
  });

  // =========================================================================
  // Image Download (for Mobile)
  // =========================================================================

  /// Get list of images for a session
  /// Returns image metadata without full image data
  Future<List<CapturedImage>> getSessionImages(int sessionId);

  /// Get thumbnail preview of an image (JPEG format, ~512x512)
  /// Returns compressed JPEG data for display in UI
  Future<Uint8List> getImageThumbnail(int imageId);

  /// Download full image data with progress tracking
  /// Downloads the full FITS file and saves to localPath
  /// Optionally calls onProgress with download percentage (0.0 to 1.0)
  Future<void> downloadImage(
    int imageId,
    String localPath, {
    void Function(double)? onProgress,
  });
}
