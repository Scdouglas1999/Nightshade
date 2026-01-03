import 'dart:async';
import 'dart:typed_data';
import 'package:nightshade_bridge/src/api.dart' as bridge_api;
import '../models/imaging/imaging_models.dart' show FrameType, ImageStats, CapturedImage;
import '../models/equipment_profile.dart';
import '../models/phd2_models.dart' hide Phd2StarImage;
import '../models/settings/app_settings.dart' as models;
import '../providers/settings_provider.dart' hide AppSettings;

/// Re-export Phd2StarImage from bridge for backend compatibility
typedef Phd2StarImage = bridge_api.Phd2StarImage;

/// Event severity levels
enum EventSeverity {
  info,
  warning,
  error,
  critical,
}

/// Event categories
enum EventCategory {
  equipment,
  imaging,
  guiding,
  sequencer,
  safety,
  system,
  polarAlignment,
}

/// Nightshade event
class NightshadeEvent {
  final int timestamp;
  final EventSeverity severity;
  final EventCategory category;
  final String eventType;
  final Map<String, dynamic> data;

  NightshadeEvent({
    required this.timestamp,
    required this.severity,
    required this.category,
    required this.eventType,
    required this.data,
  });
}

/// Device types supported by Nightshade
enum DeviceType {
  camera,
  mount,
  focuser,
  filterWheel,
  guider,
  dome,
  rotator,
  weather,
  safetyMonitor,
  switch_,
  coverCalibrator,
}

/// Driver backend type
enum DriverType {
  ascom,
  alpaca,
  indi,
  native,
  simulator,
}

/// Device connection state
enum ConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

/// Information about a discovered device
class DeviceInfo {
  final String id;
  final String name;
  final DeviceType deviceType;
  final DriverType driverType;
  final String description;
  final String driverVersion;

  DeviceInfo({
    required this.id,
    required this.name,
    required this.deviceType,
    required this.driverType,
    required this.description,
    required this.driverVersion,
  });
}

/// Camera operational state
enum CameraState {
  idle,
  waiting,
  exposing,
  reading,
  download,
  error,
}

// FrameType is now imported from imaging_models.dart
// This enum definition is kept for backward compatibility but should not be used
// Import FrameType from 'package:nightshade_core/src/models/imaging/imaging_models.dart' instead

/// Image statistics result
class ImageStatsResult {
  final double min;
  final double max;
  final double mean;
  final double median;
  final double stdDev;
  final double? hfr;
  final int starCount;

  ImageStatsResult({
    required this.min,
    required this.max,
    required this.mean,
    required this.median,
    required this.stdDev,
    this.hfr,
    required this.starCount,
  });
}

/// Captured image result
class CapturedImageResult {
  final int width;
  final int height;
  final List<int> displayData;  // RGB (width*height*3) if isColor=true, grayscale (width*height) if isColor=false
  final List<int> histogram;
  final ImageStatsResult stats;
  final double exposureTime;
  final String timestamp;
  final bool isColor;  // true if displayData is RGB, false if grayscale

  CapturedImageResult({
    required this.width,
    required this.height,
    required this.displayData,
    required this.histogram,
    required this.stats,
    required this.exposureTime,
    required this.timestamp,
    this.isColor = false,  // default to grayscale for backward compatibility
  });
}

/// Side of pier for German Equatorial mounts
enum PierSide {
  east,
  west,
  unknown,
}

// TrackingRate is defined in equipment_models.dart

/// PHD2 guiding status
class Phd2Status {
  final String state;
  final bool connected;
  final double rmsRa;
  final double rmsDec;
  final double rmsTotal;
  final double snr;
  final double starMass;
  final double avgDistance;

  Phd2Status({
    required this.state,
    required this.connected,
    this.rmsRa = 0.0,
    this.rmsDec = 0.0,
    this.rmsTotal = 0.0,
    this.snr = 0.0,
    this.starMass = 0.0,
    this.avgDistance = 0.0,
  });

  Map<String, dynamic> toJson() => {
    'state': state,
    'connected': connected,
    'rmsRa': rmsRa,
    'rmsDec': rmsDec,
    'rmsTotal': rmsTotal,
    'snr': snr,
    'starMass': starMass,
    'avgDistance': avgDistance,
  };
}

/// Plate solve result
class PlateSolveResult {
  final bool success;
  final double ra;
  final double dec;
  final double pixelScale;
  final double rotation;
  final double fieldWidth;
  final double fieldHeight;
  final double solveTimeSecs;
  final String? error;

  PlateSolveResult({
    required this.success,
    required this.ra,
    required this.dec,
    required this.pixelScale,
    required this.rotation,
    required this.fieldWidth,
    required this.fieldHeight,
    required this.solveTimeSecs,
    this.error,
  });
}

/// Sequencer status
class SequencerStatus {
  final String state;
  final String? currentNodeId;
  final String? currentNodeName;
  final double progress;
  final String? message;

  SequencerStatus({
    required this.state,
    this.currentNodeId,
    this.currentNodeName,
    required this.progress,
    this.message,
  });
}

/// Checkpoint information for crash recovery
class CheckpointInfo {
  final String sequenceName;
  final DateTime timestamp;
  final int completedExposures;
  final double completedIntegrationSecs;
  final bool canResume;
  final int ageSeconds;

  CheckpointInfo({
    required this.sequenceName,
    required this.timestamp,
    required this.completedExposures,
    required this.completedIntegrationSecs,
    required this.canResume,
    required this.ageSeconds,
  });

  Map<String, dynamic> toJson() => {
    'sequenceName': sequenceName,
    'timestamp': timestamp.toIso8601String(),
    'completedExposures': completedExposures,
    'completedIntegrationSecs': completedIntegrationSecs,
    'canResume': canResume,
    'ageSeconds': ageSeconds,
  };

  factory CheckpointInfo.fromJson(Map<String, dynamic> json) {
    return CheckpointInfo(
      sequenceName: json['sequenceName'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      completedExposures: json['completedExposures'] as int,
      completedIntegrationSecs: (json['completedIntegrationSecs'] as num).toDouble(),
      canResume: json['canResume'] as bool,
      ageSeconds: json['ageSeconds'] as int,
    );
  }
}

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
  Future<void> cameraStartExposure({
    required String deviceId,
    required double exposureTime,
    required FrameType frameType,
    required int gain,
    required int offset,
    int binX = 1,
    int binY = 1,
    int? x,
    int? y,
    int? width,
    int? height,
  });

  /// Abort current camera exposure
  Future<void> cameraAbortExposure(String deviceId);

  /// Get the last captured image
  Future<CapturedImageResult?> cameraGetLastImage(String deviceId);

  /// Get the last captured raw image data (u16 pixels)
  Future<List<int>> getLastRawImageData();

  /// Save FITS file to disk
  Future<void> saveFitsFile({
    required String filePath,
    required int width,
    required int height,
    required List<int> data,
    required bridge_api.FitsWriteHeader headerData,
  });

  /// Set camera cooling
  Future<void> cameraSetCooling({
    required String deviceId,
    required bool enabled,
    double? targetTemp,
  });

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
  Future<bridge_api.AutofocusResultApi> autofocusStart({
    required String deviceId,
    required String cameraId,
    required double exposureTime,
    required int stepSize,
    required int stepsOut,
    String method = 'VCurve',
    int binning = 1,
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
  });

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
  /// Note: Status classes are defined in nightshade_bridge
  Future<dynamic> getCameraStatus(String deviceId);

  /// Get mount status
  Future<dynamic> getMountStatus(String deviceId);

  /// Get focuser status
  Future<dynamic> getFocuserStatus(String deviceId);

  /// Get filter wheel status
  Future<dynamic> getFilterWheelStatus(String deviceId);

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
  });

  /// Stop the polar alignment process
  Future<void> stopPolarAlignment();

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
  Future<void> downloadImage(int imageId, String localPath, {void Function(double)? onProgress});

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


