import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:nightshade_core/src/database/database.dart';

/// Creates an in-memory database for testing
///
/// This function creates a new NightshadeDatabase instance that stores
/// all data in memory. The database is isolated for each test and will
/// be automatically cleaned up when the test completes.
///
/// Usage in tests:
/// ```dart
/// late NightshadeDatabase db;
///
/// setUp(() {
///   db = createTestDatabase();
/// });
///
/// tearDown(() async {
///   await db.close();
/// });
/// ```
NightshadeDatabase createTestDatabase() {
  return NightshadeDatabase.forTesting(
    NativeDatabase.memory(),
  );
}

/// Helper class for database test fixtures
class DatabaseTestFixtures {
  /// Creates a sample equipment profile companion for insertion
  static EquipmentProfilesCompanion sampleProfileCompanion({
    String name = 'Test Profile',
    String? cameraDeviceId = 'test-camera',
    String? mountDeviceId = 'test-mount',
    bool isActive = true,
  }) {
    return EquipmentProfilesCompanion.insert(
      name: name,
      description: const Value('Test equipment profile'),
      cameraDeviceId: Value(cameraDeviceId),
      mountDeviceId: Value(mountDeviceId),
      focuserDeviceId: const Value(null),
      filterWheelDeviceId: const Value(null),
      rotatorDeviceId: const Value(null),
      domeDeviceId: const Value(null),
      weatherDeviceId: const Value(null),
      safetyMonitorDeviceId: const Value(null),
      cameraSettings: const Value('{}'),
      mountSettings: const Value('{}'),
      focuserSettings: const Value('{}'),
      filterWheelSettings: const Value('{}'),
      rotatorSettings: const Value(null),
      domeSettings: const Value(null),
      weatherSettings: const Value(null),
      safetyMonitorSettings: const Value(null),
      isActive: isActive,
    );
  }

  /// Creates a sample target companion for insertion
  static TargetsCompanion sampleTargetCompanion({
    String name = 'M31',
    double ra = 10.6847,
    double dec = 41.2689,
    String objectType = 'Galaxy',
  }) {
    return TargetsCompanion.insert(
      name: name,
      catalogId: Value('NGC 224'),
      ra: ra,
      dec: dec,
      objectType: objectType,
      magnitude: const Value(3.4),
      surfaceBrightness: const Value(13.5),
      size: const Value(178.0),
      constellation: const Value('Andromeda'),
      description: const Value('Andromeda Galaxy'),
      notes: const Value(''),
      priority: const Value(5),
      isFavorite: const Value(false),
      tags: const Value('[]'),
      customData: const Value('{}'),
    );
  }

  /// Creates a sample imaging session companion for insertion
  static ImagingSessionsCompanion sampleSessionCompanion({
    String? targetId,
    String? profileId,
    DateTime? startTime,
    String status = 'active',
  }) {
    return ImagingSessionsCompanion.insert(
      targetId: Value(targetId),
      profileId: Value(profileId),
      startTime: startTime ?? DateTime.now(),
      endTime: const Value(null),
      status: status,
      totalFrames: const Value(0),
      acceptedFrames: const Value(0),
      totalExposureTime: const Value(0.0),
      averageHfr: const Value(null),
      averageFwhm: const Value(null),
      notes: const Value(''),
      weatherConditions: const Value('{}'),
      equipmentSettings: const Value('{}'),
    );
  }

  /// Creates a sample captured image companion for insertion
  static CapturedImagesCompanion sampleImageCompanion({
    required String sessionId,
    String? targetId,
    String frameType = 'light',
    double exposureTime = 120.0,
    String filePath = '/path/to/test.fits',
  }) {
    return CapturedImagesCompanion.insert(
      sessionId: sessionId,
      targetId: Value(targetId),
      filePath: filePath,
      frameType: frameType,
      exposureTime: exposureTime,
      capturedAt: DateTime.now(),
      gain: const Value(100),
      offset: const Value(50),
      binningX: const Value(1),
      binningY: const Value(1),
      temperature: const Value(-10.0),
      filter: const Value('Luminance'),
      width: const Value(4656),
      height: const Value(3520),
      mean: const Value(1500.0),
      median: const Value(1450.0),
      stdDev: const Value(250.0),
      min: const Value(100.0),
      max: const Value(65535.0),
      starCount: const Value(125),
      hfr: const Value(2.5),
      fwhm: const Value(3.2),
      eccentricity: const Value(0.15),
      snr: const Value(6.0),
      isAccepted: const Value(true),
      rejectionReason: const Value(null),
    );
  }

  /// Creates a sample sequence companion for insertion
  static SequencesCompanion sampleSequenceCompanion({
    String name = 'Test Sequence',
    bool isTemplate = false,
  }) {
    return SequencesCompanion.insert(
      name: name,
      description: const Value('Test imaging sequence'),
      isTemplate: isTemplate,
      rootNodeId: const Value(null),
      variables: const Value('{}'),
    );
  }

  /// Creates a sample sequence node companion for insertion
  static SequenceNodesCompanion sampleSequenceNodeCompanion({
    required String sequenceId,
    required String nodeId,
    String nodeType = 'instruction',
    String? parentNodeId,
    int orderIndex = 0,
  }) {
    return SequenceNodesCompanion.insert(
      sequenceId: sequenceId,
      nodeId: nodeId,
      nodeType: nodeType,
      parentNodeId: Value(parentNodeId),
      orderIndex: orderIndex,
      targetId: const Value(null),
      config: const Value('{}'),
      state: const Value('{}'),
      isEnabled: const Value(true),
    );
  }

  /// Creates a sample app settings companion for insertion
  static AppSettingsCompanion sampleSettingCompanion({
    required String key,
    required String value,
  }) {
    return AppSettingsCompanion.insert(
      key: key,
      value: value,
    );
  }
}
