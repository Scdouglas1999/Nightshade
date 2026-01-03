import 'package:drift/drift.dart';

/// Equipment profiles table
/// Stores different equipment configurations that can be selected
@DataClassName('EquipmentProfile')
@TableIndex(name: 'idx_profiles_name', columns: {#name})
@TableIndex(name: 'idx_profiles_active', columns: {#isActive})
class EquipmentProfiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get description => text().nullable()();
  
  // Device identifiers (driver-specific IDs)
  TextColumn get cameraId => text().nullable()();
  TextColumn get mountId => text().nullable()();
  TextColumn get focuserId => text().nullable()();
  TextColumn get filterWheelId => text().nullable()();
  TextColumn get guiderId => text().nullable()();
  TextColumn get rotatorId => text().nullable()();
  TextColumn get domeId => text().nullable()();
  TextColumn get weatherId => text().nullable()();
  TextColumn get coverCalibratorId => text().nullable()();
  
  // Optical setup
  RealColumn get focalLength => real().withDefault(const Constant(0.0))();
  RealColumn get aperture => real().withDefault(const Constant(0.0))();
  RealColumn get focalRatio => real().nullable()();
  
  // Camera settings defaults
  IntColumn get defaultGain => integer().nullable()();
  IntColumn get defaultOffset => integer().nullable()();
  IntColumn get defaultBinX => integer().withDefault(const Constant(1))();
  IntColumn get defaultBinY => integer().withDefault(const Constant(1))();
  RealColumn get defaultCoolingTemp => real().nullable()();
  
  // Filter configuration (JSON array of filter names)
  TextColumn get filterNames => text().nullable()();
  // Filter focus offsets (JSON object mapping filter name to offset)
  TextColumn get filterFocusOffsets => text().nullable()();
  
  // Timestamps
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  
  // Flag for the currently active profile
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();
}





