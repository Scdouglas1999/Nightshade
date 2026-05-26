import 'dart:async';
import 'dart:typed_data';

import 'package:nightshade_bridge/nightshade_bridge.dart'
    show CameraRecommendedSettings;

import '../../models/backend/backend_types.dart';
import '../../models/imaging/imaging_models.dart' show FrameType;

/// Role interface covering driver-bound device operations.
///
/// What this role owns:
///   * Device discovery (native, INDI, Alpaca, ASCOM).
///   * Connect / disconnect of any device the suite supports.
///   * Per-device-class control: camera, mount, focuser + autofocus, filter
///     wheel, rotator.
///   * Per-device capability + status queries.
///   * Device health / heartbeat monitoring.
///
/// What this role deliberately does NOT own:
///   * The event stream — see [DiagnosticsBackend].
///   * Image processing / plate solving — see [ImagingBackend]. Camera
///     capture lives here (it is a device command); turning pixel buffers
///     into stats, stretches, debayers, or solved coordinates lives in
///     [ImagingBackend].
///   * Guiding control (PHD2 + generic guider) — see [GuidingBackend].
///   * Sequencer / recovery / checkpoint — see [SequencerBackend].
///
/// Note: autofocus is included here despite straddling focuser + camera —
/// it is initiated against a focuser device id, the autofocus loop is
/// owned by the focuser/camera drivers in Rust, and the orchestration is
/// stateless from the Dart side.
abstract class DeviceBackend {
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

  /// Capture a live-view preview JPEG from the camera when the driver supports it.
  ///
  /// Throws [NightshadeError] when the driver rejects the operation. Remote
  /// clients should treat HTTP 503 from the headless host as "preview unavailable".
  Future<Uint8List> cameraLiveViewFrame(String deviceId);

  /// Get the last captured raw image data (u16 pixels) for a specific device
  Future<List<int>> getLastRawImageData(String deviceId);

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

  /// Query the camera SDK for manufacturer-recommended gain/offset values.
  ///
  /// Returns a [CameraRecommendedSettings] with whatever the vendor SDK
  /// reports. All fields are `null` on cameras whose SDK does not expose
  /// per-camera recommendations (Touptek, Player One, Atik, FLI, Moravian,
  /// ASCOM, Alpaca, INDI, gphoto2/Fujifilm). Callers MUST treat `null` as
  /// "no recommendation available" and never fabricate values.
  Future<CameraRecommendedSettings> cameraGetRecommendedSettings(
      String deviceId);

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

  /// Set filter names
  Future<void> filterWheelSetNames(String deviceId, List<String> names);

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
