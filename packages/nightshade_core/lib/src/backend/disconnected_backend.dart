import 'dart:async';
import 'dart:typed_data';
import 'package:nightshade_bridge/src/api.dart' as bridge_api;
import '../models/imaging/imaging_models.dart';
import '../models/equipment_profile.dart';
import '../models/phd2_models.dart' hide Phd2StarImage;
import '../models/settings/app_settings.dart' as models;
import '../providers/settings_provider.dart' hide AppSettings;
import 'nightshade_backend.dart';

/// A backend implementation that represents a disconnected state.
/// 
/// This is the default state for the mobile app. It throws clear, user-friendly
/// exceptions for all operations, ensuring that the app never attempts to
/// execute local logic (like FFI) when it should be acting as a thin client.
class DisconnectedBackend implements NightshadeBackend {
  final _eventController = StreamController<NightshadeEvent>.broadcast();

  @override
  Stream<NightshadeEvent> get eventStream => _eventController.stream;

  Never _throwNotConnected() {
    throw Exception(
      'Not connected to server. Please connect to a Nightshade Headless Server first.',
    );
  }

  @override
  Future<List<DeviceInfo>> discoverDevices(DeviceType deviceType) async {
    _throwNotConnected();
  }

  @override
  Future<List<DeviceInfo>> discoverIndiAtAddress(String host, int port) async {
    _throwNotConnected();
  }

  @override
  Future<List<DeviceInfo>> discoverAlpacaAtAddress(String host, int port) async {
    _throwNotConnected();
  }

  @override
  Future<void> connectDevice(DeviceType deviceType, String deviceId) async {
    _throwNotConnected();
  }

  @override
  Future<void> disconnectDevice(DeviceType deviceType, String deviceId) async {
    _throwNotConnected();
  }

  @override
  Future<List<DeviceInfo>> getConnectedDevices() async {
    _throwNotConnected();
  }

  @override
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
  }) async {
    _throwNotConnected();
  }

  @override
  Future<void> cameraAbortExposure(String deviceId) async {
    _throwNotConnected();
  }

  @override
  Future<CapturedImageResult?> cameraGetLastImage(String deviceId) async {
    _throwNotConnected();
  }

  @override
  Future<void> cameraSetCooling({
    required String deviceId,
    required bool enabled,
    double? targetTemp,
  }) async {
    _throwNotConnected();
  }

  @override
  Future<void> cameraSetGain(String deviceId, int gain) async {
    _throwNotConnected();
  }

  @override
  Future<void> cameraSetOffset(String deviceId, int offset) async {
    _throwNotConnected();
  }

  @override
  Future<void> mountSlewToCoordinates(String deviceId, double ra, double dec) async {
    _throwNotConnected();
  }

  @override
  Future<void> mountSync(String deviceId, double ra, double dec) async {
    _throwNotConnected();
  }

  @override
  Future<void> mountPark(String deviceId) async {
    _throwNotConnected();
  }

  @override
  Future<void> mountUnpark(String deviceId) async {
    _throwNotConnected();
  }

  @override
  Future<void> mountSetTracking(String deviceId, bool enabled) async {
    _throwNotConnected();
  }

  @override
  Future<void> mountPulseGuide({
    required String deviceId,
    required String direction,
    required int durationMs,
  }) async {
    _throwNotConnected();
  }

  @override
  Future<void> mountAbort(String deviceId) async {
    _throwNotConnected();
  }

  @override
  Future<dynamic> mountGetStatus(String deviceId) async {
    _throwNotConnected();
  }

  @override
  Future<void> mountSetTrackingRate(String deviceId, int rate) async {
    _throwNotConnected();
  }

  @override
  Future<void> mountMoveAxis(String deviceId, int axis, double rate) async {
    _throwNotConnected();
  }

  @override
  Future<void> focuserMoveTo(String deviceId, int position) async {
    _throwNotConnected();
  }

  @override
  Future<void> focuserMoveRelative(String deviceId, int delta) async {
    _throwNotConnected();
  }

  @override
  Future<void> focuserHalt(String deviceId) async {}

  @override
  Future<bridge_api.AutofocusResultApi> autofocusStart({
    required String deviceId,
    required String cameraId,
    required double exposureTime,
    required int stepSize,
    required int stepsOut,
    String method = 'VCurve',
    int binning = 1,
  }) async {
    _throwNotConnected();
  }

  @override
  Future<void> autofocusCancel() async {}

  // =========================================================================
  // Filter Wheel Control

  @override
  Future<void> filterWheelSetPosition(String deviceId, int position) async {
    _throwNotConnected();
  }

  @override
  Future<void> phd2Connect({String host = 'localhost', int port = 4400}) async {
    _throwNotConnected();
  }

  @override
  Future<void> phd2Disconnect() async {
    _throwNotConnected();
  }

  @override
  Future<void> phd2StartGuiding({
    double settlePixels = 1.0,
    double settleTime = 10.0,
    double settleTimeout = 60.0,
  }) async {
    _throwNotConnected();
  }

  @override
  Future<void> phd2StopGuiding() async {
    _throwNotConnected();
  }

  @override
  Future<void> phd2Dither({
    double amount = 5.0,
    bool raOnly = false,
    double settlePixels = 1.0,
    double settleTime = 10.0,
    double settleTimeout = 60.0,
  }) async {
    _throwNotConnected();
  }

  @override
  Future<Phd2Status> phd2GetStatus() async {
    _throwNotConnected();
  }

  @override
  Future<Phd2StarImage> phd2GetStarImage({int size = 50}) async {
    _throwNotConnected();
  }

  @override
  Future<List<String>> phd2GetAlgoParamNames({required String axis}) async {
    _throwNotConnected();
  }

  @override
  Future<double> phd2GetAlgoParam({
    required String axis,
    required String name,
  }) async {
    _throwNotConnected();
  }

  @override
  Future<void> phd2SetAlgoParam({
    required String axis,
    required String name,
    required double value,
  }) async {
    _throwNotConnected();
  }

  @override
  Future<void> phd2SetPaused(bool paused) async {
    _throwNotConnected();
  }

  @override
  Future<void> phd2ClearCalibration({String which = 'both'}) async {
    _throwNotConnected();
  }

  @override
  Future<void> phd2FlipCalibration() async {
    _throwNotConnected();
  }

  @override
  Future<Phd2CalibrationData> phd2GetCalibrationData() async {
    _throwNotConnected();
  }

  @override
  Future<(double, double)> phd2FindStar() async {
    _throwNotConnected();
  }

  @override
  Future<void> phd2SetLockPosition({
    required double x,
    required double y,
    bool exact = false,
  }) async {
    _throwNotConnected();
  }

  @override
  Future<(double, double)> phd2GetLockPosition() async {
    _throwNotConnected();
  }

  @override
  Future<void> phd2Loop() async {
    _throwNotConnected();
  }

  @override
  Future<void> phd2DeselectStar() async {
    _throwNotConnected();
  }

  @override
  Future<PlateSolveResult> plateSolve({
    required String imagePath,
    double? ra,
    double? dec,
    double? fovDegrees,
  }) async {
    _throwNotConnected();
  }

  @override
  Future<void> sequencerStart() async {
    _throwNotConnected();
  }

  @override
  Future<void> sequencerStop() async {
    _throwNotConnected();
  }

  @override
  Future<void> sequencerPause() async {
    _throwNotConnected();
  }

  @override
  Future<void> sequencerResume() async {
    _throwNotConnected();
  }

  @override
  Future<void> sequencerLoadJson(String json) async {
    _throwNotConnected();
  }

  @override
  Future<void> sequencerSetSimulationMode(bool enabled) async {
    _throwNotConnected();
  }

  @override
  Future<void> sequencerSetDevices({
    String? cameraId,
    String? mountId,
    String? focuserId,
    String? filterwheelId,
    String? rotatorId,
    List<String>? filterNames,
  }) async {
    _throwNotConnected();
  }

  @override
  Future<SequencerStatus> sequencerGetStatus() async {
    _throwNotConnected();
  }

  // =========================================================================
  // Checkpoint / Crash Recovery
  // =========================================================================

  @override
  Future<void> sequencerSetCheckpointDir(String path) async {
    _throwNotConnected();
  }

  @override
  Future<bool> hasCheckpoint() async {
    _throwNotConnected();
  }

  @override
  Future<CheckpointInfo?> getCheckpointInfo() async {
    _throwNotConnected();
  }

  @override
  Future<void> resumeFromCheckpoint() async {
    _throwNotConnected();
  }

  @override
  Future<void> discardCheckpoint() async {
    _throwNotConnected();
  }

  @override
  Future<void> saveCheckpoint() async {
    _throwNotConnected();
  }

  @override
  Future<LocationSettings> getLocationFromInternet() async {
    _throwNotConnected();
  }

  // =========================================================================
  // Equipment Status
  // =========================================================================

  @override
  Future<dynamic> getCameraStatus(String deviceId) async {
    _throwNotConnected();
  }

  @override
  Future<dynamic> getMountStatus(String deviceId) async {
    _throwNotConnected();
  }

  @override
  Future<dynamic> getFocuserStatus(String deviceId) async {
    _throwNotConnected();
  }

  @override
  Future<dynamic> getFilterWheelStatus(String deviceId) async {
    _throwNotConnected();
  }

  @override
  Future<List<String>> filterWheelGetNames(String deviceId) async {
    _throwNotConnected();
  }

  @override
  Future<void> filterWheelSetByName(String deviceId, String name) async {
    _throwNotConnected();
  }

  @override
  Future<void> rotatorMoveTo(String deviceId, double angle) async {
    _throwNotConnected();
  }

  @override
  Future<void> rotatorMoveRelative(String deviceId, double delta) async {
    _throwNotConnected();
  }

  @override
  Future<double> rotatorGetAngle(String deviceId) async {
    _throwNotConnected();
  }

  @override
  Future<void> rotatorHalt(String deviceId) async {
    _throwNotConnected();
  }

  @override
  Future<List<EquipmentProfile>> getProfiles() async {
    _throwNotConnected();
  }

  @override
  Future<void> saveProfile(EquipmentProfile profile) async {
    _throwNotConnected();
  }

  @override
  Future<void> deleteProfile(String profileId) async {
    _throwNotConnected();
  }

  @override
  Future<void> loadProfile(String profileId) async {
    _throwNotConnected();
  }

  @override
  Future<EquipmentProfile?> getActiveProfile() async {
    _throwNotConnected();
  }

  @override
  Future<models.AppSettings> getSettings() async {
    _throwNotConnected();
  }

  @override
  Future<void> updateSettings(models.AppSettings settings) async {
    _throwNotConnected();
  }

  @override
  Future<models.ObserverLocation?> getLocation() async {
    _throwNotConnected();
  }

  @override
  Future<void> setLocation(models.ObserverLocation? location) async {
    _throwNotConnected();
  }

  @override
  Future<ImageStats> getImageStats(int width, int height, Uint16List data) async {
    _throwNotConnected();
  }

  @override
  Future<Uint8List> autoStretchImage(int width, int height, Uint16List data) async {
    _throwNotConnected();
  }

  @override
  Future<Uint8List> debayerImage(
    int width,
    int height,
    Uint16List data,
    String pattern,
    String algorithm,
  ) async {
    _throwNotConnected();
  }

  // =========================================================================
  // Polar Alignment
  // =========================================================================

  final _polarAlignController = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get polarAlignmentEvents => _polarAlignController.stream;

  @override
  Future<void> startPolarAlignment({
    required double exposureTime,
    required double stepSize,
    required int binning,
    required bool isNorth,
    required bool manualRotation,
    required bool rotateEast,
  }) async {
    _throwNotConnected();
  }

  @override
  Future<void> stopPolarAlignment() async {
    _throwNotConnected();
  }

  @override
  Future<List<CapturedImage>> getSessionImages(int sessionId) async {
    _throwNotConnected();
  }

  @override
  Future<Uint8List> getImageThumbnail(int imageId) async {
    _throwNotConnected();
  }

  @override
  Future<void> downloadImage(int imageId, String localPath, {void Function(double)? onProgress}) async {
    _throwNotConnected();
  }

  @override
  Future<List<int>> getLastRawImageData() async {
    _throwNotConnected();
  }

  @override
  Future<void> saveFitsFile({
    required String filePath,
    required int width,
    required int height,
    required List<int> data,
    required bridge_api.FitsWriteHeader headerData,
  }) async {
    _throwNotConnected();
  }

  @override
  Future<void> startDeviceHeartbeat({
    required DeviceType deviceType,
    required String deviceId,
    required int intervalMs,
  }) async {
    _throwNotConnected();
  }

  @override
  Future<void> stopDeviceHeartbeat(String deviceId) async {
    _throwNotConnected();
  }

  @override
  Future<(int, bool)> getDeviceHealth(String deviceId) async {
    _throwNotConnected();
  }
}
