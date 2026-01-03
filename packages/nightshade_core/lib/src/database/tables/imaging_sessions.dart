import 'package:drift/drift.dart';

import 'equipment_profiles.dart';
import 'targets.dart';

/// Imaging sessions table
/// Records each imaging session with statistics and metadata
@DataClassName('ImagingSession')
@TableIndex(name: 'idx_sessions_target', columns: {#targetId})
@TableIndex(name: 'idx_sessions_profile', columns: {#profileId})
@TableIndex(name: 'idx_sessions_start', columns: {#startTime})
@TableIndex(name: 'idx_sessions_status', columns: {#status})
class ImagingSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().nullable()();
  
  // Foreign keys
  IntColumn get profileId => integer().nullable().references(EquipmentProfiles, #id)();
  IntColumn get targetId => integer().nullable().references(Targets, #id)();
  
  // Session timing
  DateTimeColumn get startTime => dateTime()();
  DateTimeColumn get endTime => dateTime().nullable()();
  
  // Statistics
  IntColumn get totalExposures => integer().withDefault(const Constant(0))();
  IntColumn get successfulExposures => integer().withDefault(const Constant(0))();
  IntColumn get failedExposures => integer().withDefault(const Constant(0))();
  RealColumn get totalIntegrationSecs => real().withDefault(const Constant(0.0))();
  
  // Weather/conditions at session time
  RealColumn get avgTemperature => real().nullable()();
  RealColumn get avgHumidity => real().nullable()();
  RealColumn get avgSeeing => real().nullable()();
  
  // Performance metrics
  RealColumn get avgHfr => real().nullable()();
  RealColumn get avgGuidingRms => real().nullable()();
  IntColumn get autofocusCount => integer().withDefault(const Constant(0))();
  
  // Notes
  TextColumn get notes => text().nullable()();
  
  // Session status
  TextColumn get status => text().withDefault(const Constant('completed'))();
  // completed, aborted, error
}

