import 'dart:async';
import 'dart:typed_data';
import 'package:nightshade_bridge/src/api/plate_solve.dart'
    show PlateSolveResult;
import '../models/autofocus_progress.dart' show StarCrop;
import '../models/imaging/imaging_models.dart'
    show FrameType, ImageStats, CapturedImage;
import '../models/equipment_profile.dart';
import '../models/phd2_models.dart';
import '../models/settings/app_settings.dart' as models;
import '../providers/settings_provider.dart' show LocationSettings;

// Import extracted backend types (pure Dart, no bridge dependency)
import '../models/backend/backend_types.dart';

// Re-export backend types for backward compatibility
export '../models/backend/backend_types.dart';
// Re-export the FRB-canonical PlateSolveResult so callers can keep importing
// just `nightshade_backend.dart` after the model-layer copy was deleted.
export 'package:nightshade_bridge/src/api/plate_solve.dart'
    show PlateSolveResult;

/// Abstract backend interface for device control
///
/// This interface defines all device control methods that can be implemented
/// by different backends (FFI, Network, etc.)
abstract class NightshadeBackend {
  /// Event stream for backend events
  Stream<NightshadeEvent> get eventStream;

  /// Event stream for polar alignment updates
  Stream<Map<String, dynamic>> get polarAlignmentEvents;

  // =========================================================================
  // Lifecycle Management
  // =========================================================================

  /// Dispose of backend resources.
  ///
  /// Must be called when the backend is no longer needed to prevent
  /// memory leaks and ensure proper cleanup of streams, subscriptions,
  /// and network connections.
  void dispose();

  // =========================================================================
  // Device Discovery & Connection
  // =========================================================================

  /// Discover available devices of a specific type
  Future<List<DeviceInfo>> discoverDevices(DeviceType deviceType);

  /// Discover INDI devices at a specific server address
  Future<List<DeviceInfo>> discoverIndiAtAddress(String host, int port);

  /// Discover Alpaca devices at a specific server address
  Future<List<DeviceInfo>> discoverAlpacaAtAddress(String host, int port);

  /// Connect to a device
  Future<void> connectDevice(DeviceType deviceType, String deviceId);

  /// Disconnect from a device
  Future<void> disconnectDevice(DeviceType deviceType, String deviceId);

  /// Get list of currently connected devices
  Future<List<DeviceInfo>> getConnectedDevices();

  // =========================================================================
  // Camera Control
  // =========================================================================

  /// Start a camera exposure
  ///
  /// [gain] and [offset] are optional - if null, the camera's current/default
  /// settings will be used. This supports cameras that don't have adjustable gain/offset.
  Future<void> cameraStartExposure({
    required String deviceId,
    required double exposureTime,
    required FrameType frameType,
    int? gain,
    int? offset,
    int binX = 1,
    int binY = 1,
    int? x,
    int? y,
    int? width,
    int? height,
  });

  /// Abort current camera exposure
  Future<void> cameraAbortExposure(String deviceId);

  /// Get the last captured image for a specific device
  Future<CapturedImageResult?> cameraGetLastImage(String deviceId);

  /// Get the last captured raw image data (u16 pixels) for a specific device
  Future<List<int>> getLastRawImageData(String deviceId);

  /// Save FITS file to disk
  Future<void> saveFitsFile({
    required String filePath,
    required int width,
    required int height,
    required List<int> data,
    required FitsWriteHeader headerData,
  });

  /// Save FITS file directly from the last captured image stored server-side.
  /// This eliminates raw pixel data transfer across FFI/network boundaries.
  /// More efficient than saveFitsFile for normal capture workflows.
  Future<void> saveFitsFromLastCapture({
    required String deviceId,
    required String filePath,
    required FitsWriteHeader headerData,
  });

  /// Clear stored image data for a specific device
  /// This frees memory when a camera is disconnected or when explicitly requested
  Future<void> clearDeviceImage(String deviceId);

  /// Set camera cooling
  Future<void> cameraSetCooling({
    required String deviceId,
    required bool enabled,
    double? targetTemp,
  });

  /// Set camera readout mode by index
  /// modeIndex: 0 = default/high quality, 1 = fast readout, etc.
  Future<void> cameraSetReadoutMode(String deviceId, int modeIndex);

  /// Set camera gain
  Future<void> cameraSetGain(String deviceId, int gain);

  /// Set camera offset
  Future<void> cameraSetOffset(String deviceId, int offset);

  // =========================================================================
  // Mount Control
  // =========================================================================

  /// Slew mount to coordinates
  Future<void> mountSlewToCoordinates(String deviceId, double ra, double dec);

  /// Sync mount to coordinates
  Future<void> mountSync(String deviceId, double ra, double dec);

  /// Park the mount
  Future<void> mountPark(String deviceId);

  /// Unpark the mount
  Future<void> mountUnpark(String deviceId);

  /// Set mount tracking
  Future<void> mountSetTracking(String deviceId, bool enabled);

  /// Pulse guide (for corrections)
  Future<void> mountPulseGuide({
    required String deviceId,
    required String direction,
    required int durationMs,
  });

  /// Abort mount slew
  Future<void> mountAbort(String deviceId);

  /// Get mount status
  Future<dynamic> mountGetStatus(String deviceId);

  /// Set mount tracking rate (0=Sidereal, 1=Lunar, 2=Solar, 3=King)
  Future<void> mountSetTrackingRate(String deviceId, int rate);

  /// Move mount axis at specified rate (degrees/second)
  /// axis: 0=RA/Azimuth (primary), 1=Dec/Altitude (secondary)
  /// rate: degrees per second (positive = N/E, negative = S/W), 0 to stop
  Future<void> mountMoveAxis(String deviceId, int axis, double rate);

  /// Slew mount to alt/az coordinates (altitude in degrees, azimuth in degrees)
  Future<void> mountSlewAltAz(String deviceId, double altitude, double azimuth);

  /// Find mount home position
  Future<void> mountFindHome(String deviceId);

  // =========================================================================
  // Focuser Control
  // =========================================================================

  /// Move focuser to absolute position
  Future<void> focuserMoveTo(String deviceId, int position);

  /// Move focuser by relative amount
  Future<void> focuserMoveRelative(String deviceId, int delta);

  /// Halt focuser movement
  Future<void> focuserHalt(String deviceId);

  /// Run autofocus
  /// Returns the full autofocus result including focus curve data
  Future<AutofocusResult> autofocusStart({
    required String deviceId,
    required String cameraId,
    required double exposureTime,
    required int stepSize,
    required int stepsOut,
    String method = 'VCurve',
    int binning = 1,
    String curveFitting = 'Hyperbolic',
    int numberOfAttempts = 1,
    int exposuresPerPoint = 1,
    double rSquaredThreshold = 0.7,
    double outerCropRatio = 1.0,
    double innerCropRatio = 0.0,
    int useBrightestNStars = 0,
    int focuserSettleTimeMs = 500,
    String backlashCompMethod = 'Overshoot',
    int backlashIn = 350,
    int backlashOut = 0,
  });

  /// Cancel autofocus
  Future<void> autofocusCancel();

  // =========================================================================
  // Filter Wheel Control
  // =========================================================================

  /// Set filter wheel position
  Future<void> filterWheelSetPosition(String deviceId, int position);

  /// Get filter names
  Future<List<String>> filterWheelGetNames(String deviceId);

  /// Set filter by name
  Future<void> filterWheelSetByName(String deviceId, String name);

  // =========================================================================
  // Rotator Control
  // =========================================================================

  /// Move rotator to absolute angle
  Future<void> rotatorMoveTo(String deviceId, double angle);

  /// Move rotator by relative angle
  Future<void> rotatorMoveRelative(String deviceId, double delta);

  /// Get rotator angle
  Future<double> rotatorGetAngle(String deviceId);

  /// Halt rotator
  Future<void> rotatorHalt(String deviceId);

  /// Sync the rotator's reported sky position-angle (degrees) to [pa] without
  /// moving the hardware. Why a separate method from [rotatorMoveTo]: ASCOM
  /// IRotatorV3 distinguishes Sync (offset-only) from MoveAbsolute (motion);
  /// the "Sync to image PA" plate-solve workflow needs the Sync semantic.
  Future<void> rotatorSyncToPa(String deviceId, double pa);

  // =========================================================================
  // PHD2 Guiding
  // =========================================================================

  /// Connect to PHD2
  Future<void> phd2Connect({String host = 'localhost', int port = 4400});

  /// Disconnect from PHD2
  Future<void> phd2Disconnect();

  /// Start guiding
  Future<void> phd2StartGuiding({
    double settlePixels = 1.0,
    double settleTime = 10.0,
    double settleTimeout = 60.0,
  });

  /// Stop guiding
  Future<void> phd2StopGuiding();

  /// Dither
  Future<void> phd2Dither({
    double amount = 5.0,
    bool raOnly = false,
    double settlePixels = 1.0,
    double settleTime = 10.0,
    double settleTimeout = 60.0,
  });

  /// Get PHD2 status
  Future<Phd2Status> phd2GetStatus();

  /// Get star image from PHD2
  Future<Phd2StarImage> phd2GetStarImage({int size = 50});

  /// Get algorithm parameter names for an axis
  Future<List<String>> phd2GetAlgoParamNames({required String axis});

  /// Get algorithm parameter value
  Future<double> phd2GetAlgoParam({required String axis, required String name});

  /// Set algorithm parameter value
  Future<void> phd2SetAlgoParam({
    required String axis,
    required String name,
    required double value,
  });

  /// Pause or resume guiding
  Future<void> phd2SetPaused(bool paused);

  /// Clear calibration data
  Future<void> phd2ClearCalibration({String which = 'both'});

  /// Flip calibration (after meridian flip)
  Future<void> phd2FlipCalibration();

  /// Get current calibration data from PHD2
  Future<Phd2CalibrationData> phd2GetCalibrationData();

  /// Find a guide star automatically
  Future<(double, double)> phd2FindStar();

  /// Set guide star lock position
  Future<void> phd2SetLockPosition({
    required double x,
    required double y,
    bool exact = false,
  });

  /// Get current lock position
  Future<(double, double)> phd2GetLockPosition();

  /// Start looping exposures (without guiding)
  Future<void> phd2Loop();

  /// Deselect the current guide star
  Future<void> phd2DeselectStar();

  // =========================================================================
  // Generic Guiding (driver-agnostic)
  // =========================================================================

  /// Start guiding using the connected guider
  ///
  /// Routes to appropriate implementation (PHD2, or future guider types) based
  /// on the device ID. This abstraction allows future guider implementations
  /// to be added without changing service-level code.
  Future<void> guiderStartGuiding({
    required String deviceId,
    double settlePixels = 1.0,
    double settleTime = 10.0,
    double settleTimeout = 60.0,
  });

  /// Stop guiding on the specified guider
  Future<void> guiderStopGuiding({required String deviceId});

  /// Dither the guide star
  Future<void> guiderDither({
    required String deviceId,
    double amount = 5.0,
    bool raOnly = false,
    double settlePixels = 1.0,
    double settleTime = 10.0,
    double settleTimeout = 60.0,
  });

  /// Start guide-camera looping without issuing guide corrections.
  Future<void> guiderLoop({required String deviceId});

  /// Automatically select a guide star.
  Future<(double, double)> guiderFindStar({required String deviceId});

  /// Set the guide-star lock position.
  Future<void> guiderSetLockPosition({
    required String deviceId,
    required double x,
    required double y,
    bool exact = false,
  });

  /// Get the current guide-star lock position.
  Future<(double, double)> guiderGetLockPosition({required String deviceId});

  /// Deselect the current guide star.
  Future<void> guiderDeselectStar({required String deviceId});

  /// Fetch the latest guide star image/crop.
  Future<Phd2StarImage> guiderGetStarImage({
    required String deviceId,
    int size = 50,
  });

  /// Get the built-in guider configuration.
  Future<BuiltinGuiderConfig> builtinGuiderGetConfig();

  /// Set the built-in guider configuration.
  Future<void> builtinGuiderSetConfig(BuiltinGuiderConfig config);

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
  // Sequencer Control
  // =========================================================================

  /// Start the sequencer
  Future<void> sequencerStart();

  /// Stop the sequencer
  Future<void> sequencerStop();

  /// Pause the sequencer
  Future<void> sequencerPause();

  /// Resume the sequencer
  Future<void> sequencerResume();

  /// Skip the current node in the sequencer
  Future<void> sequencerSkip();

  /// Reset the sequencer to its initial state
  Future<void> sequencerReset();

  /// Load a sequence definition (JSON) into the sequencer
  Future<void> sequencerLoadJson(String json);

  /// Get sequencer status
  Future<SequencerStatus> sequencerGetStatus();

  /// Set simulation mode (use mock devices instead of real hardware)
  Future<void> sequencerSetSimulationMode(bool enabled);

  /// Set connected devices for the sequencer
  Future<void> sequencerSetDevices({
    String? cameraId,
    String? mountId,
    String? focuserId,
    String? filterwheelId,
    String? rotatorId,
    List<String>? filterNames,
    Map<String, int>? filterFocusOffsets,
  });

  /// Set the safety fail mode for the sequencer.
  /// Determines behavior when safety devices fail or are unavailable:
  /// - "fail_closed": Treat unavailable safety data as unsafe (enforced)
  /// - legacy aliases ("fail_open", "warn_only") are coerced to fail-closed
  Future<void> sequencerSetSafetyFailMode(String mode);

  /// Set the save path for sequencer images.
  /// This is the base directory where captured images will be saved.
  /// If null or empty, images will NOT be saved to disk.
  Future<void> sequencerSetSavePath(String? path);

  /// Update dither configuration at runtime during sequence execution.
  /// Values are propagated to the Rust executor for use by subsequent operations.
  Future<void> sequencerUpdateDitherConfig({
    required double pixels,
    required double settlePixels,
    required double settleTime,
    required double settleTimeout,
    required bool raOnly,
  });

  /// Update observer location at runtime during sequence execution.
  /// Updates the executor's stored location for altitude-based trigger evaluation.
  Future<void> sequencerUpdateLocation({
    required double latitude,
    required double longitude,
  });

  /// Update filter focus offsets at runtime during sequence execution.
  /// Propagates new offsets to the executor for focus compensation.
  Future<void> sequencerUpdateFilterOffsets(Map<String, int> offsets);

  // =========================================================================
  // Checkpoint / Crash Recovery
  // =========================================================================

  /// Set the directory for checkpoint files
  Future<void> sequencerSetCheckpointDir(String path);

  /// Check if a recoverable checkpoint exists
  Future<bool> hasCheckpoint();

  /// Get information about the current checkpoint
  Future<CheckpointInfo?> getCheckpointInfo();

  /// Resume sequence from checkpoint
  Future<void> resumeFromCheckpoint();

  /// Discard the current checkpoint
  Future<void> discardCheckpoint();

  /// Save a checkpoint of current execution state
  Future<void> saveCheckpoint();

  /// Get current location from internet (IP-based)
  Future<LocationSettings> getLocationFromInternet();

  // =========================================================================
  // Equipment Status
  // =========================================================================

  /// Get camera status
  /// Returns typed CameraStatus with all sensor and cooling information
  Future<CameraStatus> getCameraStatus(String deviceId);

  /// Get mount status
  /// Returns typed MountStatus with position, tracking, and capability flags
  Future<MountStatus> getMountStatus(String deviceId);

  /// Get focuser status
  /// Returns typed FocuserStatus with position, movement, and temperature info
  Future<FocuserStatus> getFocuserStatus(String deviceId);

  /// Get filter wheel status
  /// Returns typed FilterWheelStatus with position and filter names
  Future<FilterWheelStatus> getFilterWheelStatus(String deviceId);

  /// Get rotator status
  /// Returns typed RotatorStatus with position and movement info
  Future<RotatorStatus> getRotatorStatus(String deviceId);

  // =========================================================================
  // Device Capabilities
  // =========================================================================

  /// Get camera capabilities
  /// Returns null if the device is not connected or capabilities unavailable
  Future<CameraCapabilities?> getCameraCapabilities(String deviceId);

  /// Get mount capabilities
  /// Returns null if the device is not connected or capabilities unavailable
  Future<MountCapabilities?> getMountCapabilities(String deviceId);

  /// Get focuser capabilities
  /// Returns null if the device is not connected or capabilities unavailable
  Future<FocuserCapabilities?> getFocuserCapabilities(String deviceId);

  /// Get filter wheel capabilities
  /// Returns null if the device is not connected or capabilities unavailable
  Future<FilterWheelCapabilities?> getFilterWheelCapabilities(String deviceId);

  /// Get rotator capabilities
  /// Returns null if the device is not connected or capabilities unavailable
  Future<RotatorCapabilities?> getRotatorCapabilities(String deviceId);

  // =========================================================================
  // Equipment Profiles
  // =========================================================================

  /// Get all profiles
  Future<List<EquipmentProfile>> getProfiles();

  /// Save profile
  Future<void> saveProfile(EquipmentProfile profile);

  /// Delete profile
  Future<void> deleteProfile(String profileId);

  /// Load profile and set as active
  Future<void> loadProfile(String profileId);

  /// Get active profile
  Future<EquipmentProfile?> getActiveProfile();

  // Settings & Location
  Future<models.AppSettings> getSettings();
  Future<void> updateSettings(models.AppSettings settings);
  Future<models.ObserverLocation?> getLocation();
  Future<void> setLocation(models.ObserverLocation? location);

  // Image Processing
  Future<ImageStats> getImageStats(int width, int height, Uint16List data);
  Future<Uint8List> autoStretchImage(int width, int height, Uint16List data);

  /// Get star crops from the last captured image for autofocus UI
  Future<List<StarCrop>> getStarCropsFromLastImage(String deviceId,
      {int maxCrops = 5});
  Future<Uint8List> debayerImage(
    int width,
    int height,
    Uint16List data,
    String pattern,
    String algorithm,
  );

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
  Future<void> downloadImage(int imageId, String localPath,
      {void Function(double)? onProgress});

  // =========================================================================
  // Device Health Monitoring
  // =========================================================================

  /// Start heartbeat monitoring for a device
  ///
  /// Periodically checks if the device is responding and emits disconnect
  /// events if communication fails.
  ///
  /// # Arguments
  /// * `deviceType` - Type of device to monitor
  /// * `deviceId` - Unique identifier for the device
  /// * `intervalMs` - Heartbeat interval in milliseconds (recommended: 10000)
  Future<void> startDeviceHeartbeat({
    required DeviceType deviceType,
    required String deviceId,
    required int intervalMs,
  });

  /// Stop heartbeat monitoring for a device
  ///
  /// # Arguments
  /// * `deviceId` - The unique identifier for the device
  Future<void> stopDeviceHeartbeat(String deviceId);

  /// Check device health status
  ///
  /// Returns the last successful communication timestamp and whether
  /// the device is currently responding to heartbeat checks.
  ///
  /// # Arguments
  /// * `deviceId` - The unique identifier for the device
  ///
  /// # Returns
  /// A tuple of (last_successful_timestamp_ms, is_healthy)
  Future<(int, bool)> getDeviceHealth(String deviceId);
}
