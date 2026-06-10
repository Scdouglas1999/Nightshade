// Part of ../disconnected_backend.dart -- extracted for maintainability.
//
// Fail-closed profile, settings, image, polar-alignment, and heartbeat overrides.
part of '../disconnected_backend.dart';

mixin _DisconnectedBackendProfileAndImage on Object
    implements NightshadeBackend {
  Never _throwNotConnected();

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
  Future<List<StarCrop>> getStarCropsFromLastImage(
    String deviceId, {
    int maxCrops = 5,
  }) async {
    _throwNotConnected();
  }

  @override
  Future<PlateSolverDetection> detectPlateSolvers() async {
    _throwNotConnected();
  }

  @override
  Future<PlateSolverInfo> verifyPlateSolver(String executablePath) async {
    _throwNotConnected();
  }

  @override
  Future<PlateSolverPreference> getPlateSolverConfig() async {
    _throwNotConnected();
  }

  @override
  Future<void> setPlateSolverConfig(PlateSolverPreference pref) async {
    _throwNotConnected();
  }

  @override
  Future<void> calibrateImageFile({
    required String lightPath,
    String? darkPath,
    String? flatPath,
    String? biasPath,
    required String outputPath,
  }) async {
    _throwNotConnected();
  }

  // =========================================================================
  // Polar Alignment
  // =========================================================================

  final _polarAlignController =
      StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get polarAlignmentEvents =>
      _polarAlignController.stream;

  @override
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
  }) async {
    _throwNotConnected();
  }

  @override
  Future<void> stopPolarAlignment() async {
    _throwNotConnected();
  }

  @override
  Future<void> startAllSkyPolarAlignment({
    required double exposureTime,
    required double solveTimeout,
    required int binning,
    required bool isNorth,
    required double acceptanceThresholdArcsec,
    required double iterationCadenceSecs,
    int? gain,
    int? offset,
  }) async {
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
  Future<void> downloadImage(
    int imageId,
    String localPath, {
    void Function(double)? onProgress,
  }) async {
    _throwNotConnected();
  }

  @override
  Future<List<int>> getLastRawImageData(String deviceId) async {
    _throwNotConnected();
  }

  @override
  Future<void> saveFitsFromLastCapture({
    required String deviceId,
    required String filePath,
    required FitsWriteHeader headerData,
  }) async {
    _throwNotConnected();
  }

  @override
  Future<void> clearDeviceImage(String deviceId) async {
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
