import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';

const _uuid = Uuid();

/// Utility class for seeding the database with test data
class DatabaseSeeder {
  final NightshadeDatabase _db;

  DatabaseSeeder(this._db);

  /// Seed all test data
  Future<void> seedAll() async {
    await seedEquipmentProfiles();
    await seedTargets();
    await seedSequences();
    await seedSettings();
  }

  /// Clear all data (useful for testing)
  Future<void> clearAll() async {
    await _db.delete(_db.capturedImages).go();
    await _db.delete(_db.imageMetadata).go();
    await _db.delete(_db.imagingSessions).go();
    await _db.delete(_db.sequenceNodes).go();
    await _db.delete(_db.sequences).go();
    await _db.delete(_db.targets).go();
    await _db.delete(_db.equipmentProfiles).go();
    await _db.delete(_db.appSettings).go();
  }

  /// Seed equipment profiles
  Future<void> seedEquipmentProfiles() async {
    final profiles = [
      EquipmentProfilesCompanion.insert(
        name: 'Primary Imaging Rig',
        description: const Value('Main imaging setup with ASI2600MC'),
        cameraId: const Value('ascom:ASCOM.ASICamera2.Camera'),
        mountId: const Value('ascom:ASCOM.EQMod.Telescope'),
        focuserId: const Value('ascom:ASCOM.ZWO.Focuser'),
        filterWheelId: const Value('ascom:ASCOM.ZWO.FilterWheel'),
        focalLength: const Value(530.0),
        aperture: const Value(71.0),
        focalRatio: const Value(7.5),
        defaultGain: const Value(100),
        defaultOffset: const Value(50),
        defaultBinX: const Value(1),
        defaultBinY: const Value(1),
        defaultCoolingTemp: const Value(-10.0),
        filterNames: const Value('["L","R","G","B","Ha","OIII","SII"]'),
        filterFocusOffsets: const Value('{"L":0,"R":10,"G":5,"B":-5,"Ha":15,"OIII":20,"SII":18}'),
        isActive: const Value(true),
      ),
      EquipmentProfilesCompanion.insert(
        name: 'Wide Field Setup',
        description: const Value('Wide field with Samyang 135mm'),
        cameraId: const Value('ascom:ASCOM.ASICamera2.Camera'),
        mountId: const Value('ascom:ASCOM.EQMod.Telescope'),
        focalLength: const Value(135.0),
        aperture: const Value(67.5),
        focalRatio: const Value(2.0),
        defaultGain: const Value(200),
        defaultOffset: const Value(50),
        isActive: const Value(false),
      ),
      EquipmentProfilesCompanion.insert(
        name: 'Simulator Profile',
        description: const Value('Profile for testing with simulator devices'),
        cameraId: const Value('sim_camera_1'),
        mountId: const Value('sim_mount_1'),
        focuserId: const Value('sim_focuser_1'),
        filterWheelId: const Value('sim_filterwheel_1'),
        focalLength: const Value(800.0),
        aperture: const Value(200.0),
        focalRatio: const Value(4.0),
        defaultGain: const Value(100),
        defaultOffset: const Value(10),
        filterNames: const Value('["L","R","G","B","Ha","OIII","SII"]'),
        isActive: const Value(false),
      ),
    ];

    for (final profile in profiles) {
      await _db.into(_db.equipmentProfiles).insert(profile);
    }
  }

  /// Seed targets
  Future<void> seedTargets() async {
    // Intentionally empty - User requested no hardcoded target data.
    // Targets should be populated via CatalogManager imports or user entry.
  }

  /// Seed sequences
  Future<void> seedSequences() async {
    // Create a template sequence
    final templateId = await _db.into(_db.sequences).insert(
      SequencesCompanion.insert(
        name: 'LRGB Template',
        description: const Value('Standard LRGB imaging sequence'),
        isTemplate: const Value(true),
        estimatedDurationMins: const Value(180),
      ),
    );

    // Add nodes for the template
    final templateNodes = [
      _createSequenceNode(
        sequenceId: templateId,
        nodeType: 'instruction',
        specificType: 'autofocus',
        name: 'Initial Focus',
        orderIndex: 0,
        properties: '{"method":"v-curve","stepSize":100,"stepsOut":7}',
      ),
      _createSequenceNode(
        sequenceId: templateId,
        nodeType: 'instruction',
        specificType: 'capture',
        name: 'Luminance',
        orderIndex: 1,
        properties: '{"filter":"L","exposureTime":300,"count":20,"gain":100,"offset":50,"dither":true}',
      ),
      _createSequenceNode(
        sequenceId: templateId,
        nodeType: 'instruction',
        specificType: 'capture',
        name: 'Red',
        orderIndex: 2,
        properties: '{"filter":"R","exposureTime":180,"count":15,"gain":100,"offset":50,"dither":true}',
      ),
      _createSequenceNode(
        sequenceId: templateId,
        nodeType: 'instruction',
        specificType: 'capture',
        name: 'Green',
        orderIndex: 3,
        properties: '{"filter":"G","exposureTime":180,"count":15,"gain":100,"offset":50,"dither":true}',
      ),
      _createSequenceNode(
        sequenceId: templateId,
        nodeType: 'instruction',
        specificType: 'capture',
        name: 'Blue',
        orderIndex: 4,
        properties: '{"filter":"B","exposureTime":180,"count":15,"gain":100,"offset":50,"dither":true}',
      ),
    ];

    for (final node in templateNodes) {
      await _db.into(_db.sequenceNodes).insert(node);
    }

    // Create a narrowband template
    final narrowbandId = await _db.into(_db.sequences).insert(
      SequencesCompanion.insert(
        name: 'SHO Narrowband Template',
        description: const Value('Hubble Palette narrowband sequence'),
        isTemplate: const Value(true),
        estimatedDurationMins: const Value(360),
      ),
    );

    final narrowbandNodes = [
      _createSequenceNode(
        sequenceId: narrowbandId,
        nodeType: 'instruction',
        specificType: 'autofocus',
        name: 'Initial Focus',
        orderIndex: 0,
        properties: '{"method":"v-curve","stepSize":100,"stepsOut":7}',
      ),
      _createSequenceNode(
        sequenceId: narrowbandId,
        nodeType: 'instruction',
        specificType: 'capture',
        name: 'Sulfur II',
        orderIndex: 1,
        properties: '{"filter":"SII","exposureTime":600,"count":20,"gain":200,"offset":50,"dither":true}',
      ),
      _createSequenceNode(
        sequenceId: narrowbandId,
        nodeType: 'instruction',
        specificType: 'capture',
        name: 'Hydrogen Alpha',
        orderIndex: 2,
        properties: '{"filter":"Ha","exposureTime":600,"count":30,"gain":200,"offset":50,"dither":true}',
      ),
      _createSequenceNode(
        sequenceId: narrowbandId,
        nodeType: 'instruction',
        specificType: 'capture',
        name: 'Oxygen III',
        orderIndex: 3,
        properties: '{"filter":"OIII","exposureTime":600,"count":20,"gain":200,"offset":50,"dither":true}',
      ),
    ];

    for (final node in narrowbandNodes) {
      await _db.into(_db.sequenceNodes).insert(node);
    }
  }

  SequenceNodesCompanion _createSequenceNode({
    required int sequenceId,
    required String nodeType,
    required String specificType,
    required String name,
    required int orderIndex,
    required String properties,
    String? parentNodeId,
  }) {
    return SequenceNodesCompanion.insert(
      nodeId: _uuid.v4(),
      sequenceId: sequenceId,
      nodeType: nodeType,
      specificType: specificType,
      name: name,
      orderIndex: Value(orderIndex),
      properties: Value(properties),
      parentNodeId: Value(parentNodeId),
    );
  }

  /// Seed settings with useful defaults
  Future<void> seedSettings() async {
    final settings = {
      'theme': 'dark',
      'default_image_directory': '',
      'auto_connect_equipment': 'false',
      'observer_latitude': '40.7128',
      'observer_longitude': '-74.0060',
      'observer_elevation': '10.0',
      'plate_solve_solver': 'ASTAP',
      'plate_solve_path': '',
      'plate_solve_timeout': '60',
      'plate_solve_auto': 'true',
      'plate_solve_radius': '30.0',
      'output_format': 'FITS',
      'output_bit_depth': '16-bit',
      'file_pattern': r'$DATE_$TARGET_$FILTER_$EXPOSURE_###',
      'include_timestamp': 'true',
      'include_filter': 'true',
      'dither_enabled': 'true',
      'dither_pixels': '5',
      'dither_settle_time': '10',
      'guiding_settle_pixels': '0.5',
      'guiding_settle_time': '10',
      'guiding_settle_timeout': '60',
      'autofocus_method': 'v-curve',
      'autofocus_step_size': '100',
      'autofocus_steps_out': '7',
      'meridian_flip_enabled': 'true',
      'meridian_flip_pause_before': '5',
      'meridian_flip_auto_recenter': 'true',
    };

    for (final entry in settings.entries) {
      await _db.into(_db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: entry.key,
          value: entry.value,
        ),
      );
    }
  }
}

/// Extension method to easily seed the database
extension NightshadeDatabaseSeeding on NightshadeDatabase {
  /// Get a seeder instance
  DatabaseSeeder get seeder => DatabaseSeeder(this);
  
  /// Seed the database with test data
  Future<void> seedTestData() => seeder.seedAll();
  
  /// Clear all data from the database
  Future<void> clearAllData() => seeder.clearAll();
}