import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'tables/equipment_profiles.dart';
import 'tables/imaging_sessions.dart';
import 'tables/targets.dart';
import 'tables/sequences.dart';
import 'tables/captured_images.dart';
import 'tables/settings.dart';
import 'tables/weather_settings.dart';
import 'tables/flat_history.dart';
import 'daos/images_dao.dart';
import 'daos/equipment_profiles_dao.dart';
import 'daos/sessions_dao.dart';
import 'daos/sequences_dao.dart';
import 'daos/sequence_checkpoints_dao.dart';
import 'daos/targets_dao.dart';
import 'daos/settings_dao.dart';
import 'daos/weather_settings_dao.dart';
import 'daos/flat_history_dao.dart';

part 'database.g.dart';

/// The main database class for Nightshade
@DriftDatabase(
  tables: [
    EquipmentProfiles,
    ImagingSessions,
    Targets,
    Sequences,
    SequenceNodes,
    SequenceCheckpoints,
    CapturedImages,
    ImageMetadata,
    AppSettings,
    WeatherSettings,
    FlatHistory,
  ],
  daos: [
    ImagesDao,
    EquipmentProfilesDao,
    SessionsDao,
    SequencesDao,
    SequenceCheckpointsDao,
    TargetsDao,
    SettingsDao,
    WeatherSettingsDao,
    FlatHistoryDao,
  ],
)
class NightshadeDatabase extends _$NightshadeDatabase {
  NightshadeDatabase() : super(_openConnection());

  /// For testing with a custom QueryExecutor
  NightshadeDatabase.forTesting(QueryExecutor e) : super(e);

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
        // Insert default settings
        await _insertDefaultSettings();
      },
      beforeOpen: (details) async {
        // Enable foreign key enforcement
        await customStatement('PRAGMA foreign_keys = ON');
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // Version 2: Add indexes for better query performance
        if (from < 2) {
          // Create indexes for targets
          await m.createIndex(Index('idx_targets_name', 'CREATE INDEX idx_targets_name ON targets (name)'));
          await m.createIndex(Index('idx_targets_catalog', 'CREATE INDEX idx_targets_catalog ON targets (catalog_id)'));
          await m.createIndex(Index('idx_targets_priority', 'CREATE INDEX idx_targets_priority ON targets (priority)'));
          await m.createIndex(Index('idx_targets_favorite', 'CREATE INDEX idx_targets_favorite ON targets (is_favorite)'));
          await m.createIndex(Index('idx_targets_object_type', 'CREATE INDEX idx_targets_object_type ON targets (object_type)'));

          // Create indexes for captured_images
          await m.createIndex(Index('idx_images_session', 'CREATE INDEX idx_images_session ON captured_images (session_id)'));
          await m.createIndex(Index('idx_images_target', 'CREATE INDEX idx_images_target ON captured_images (target_id)'));
          await m.createIndex(Index('idx_images_frame_type', 'CREATE INDEX idx_images_frame_type ON captured_images (frame_type)'));
          await m.createIndex(Index('idx_images_captured_at', 'CREATE INDEX idx_images_captured_at ON captured_images (captured_at)'));
          await m.createIndex(Index('idx_images_filter', 'CREATE INDEX idx_images_filter ON captured_images (filter)'));
          await m.createIndex(Index('idx_images_accepted', 'CREATE INDEX idx_images_accepted ON captured_images (is_accepted)'));
          await m.createIndex(Index('idx_images_session_frame', 'CREATE INDEX idx_images_session_frame ON captured_images (session_id, frame_type)'));

          // Create indexes for imaging_sessions
          await m.createIndex(Index('idx_sessions_target', 'CREATE INDEX idx_sessions_target ON imaging_sessions (target_id)'));
          await m.createIndex(Index('idx_sessions_profile', 'CREATE INDEX idx_sessions_profile ON imaging_sessions (profile_id)'));
          await m.createIndex(Index('idx_sessions_start', 'CREATE INDEX idx_sessions_start ON imaging_sessions (start_time)'));
          await m.createIndex(Index('idx_sessions_status', 'CREATE INDEX idx_sessions_status ON imaging_sessions (status)'));

          // Create indexes for sequences
          await m.createIndex(Index('idx_sequences_name', 'CREATE INDEX idx_sequences_name ON sequences (name)'));
          await m.createIndex(Index('idx_sequences_template', 'CREATE INDEX idx_sequences_template ON sequences (is_template)'));
          await m.createIndex(Index('idx_sequences_updated', 'CREATE INDEX idx_sequences_updated ON sequences (updated_at)'));

          // Create indexes for sequence_nodes
          await m.createIndex(Index('idx_nodes_sequence', 'CREATE INDEX idx_nodes_sequence ON sequence_nodes (sequence_id)'));
          await m.createIndex(Index('idx_nodes_parent', 'CREATE INDEX idx_nodes_parent ON sequence_nodes (parent_node_id)'));
          await m.createIndex(Index('idx_nodes_target', 'CREATE INDEX idx_nodes_target ON sequence_nodes (target_id)'));
          await m.createIndex(Index('idx_nodes_type', 'CREATE INDEX idx_nodes_type ON sequence_nodes (node_type)'));
          await m.createIndex(Index('idx_nodes_node_id', 'CREATE INDEX idx_nodes_node_id ON sequence_nodes (node_id)'));

          // Create indexes for image_metadata
          await m.createIndex(Index('idx_metadata_image', 'CREATE INDEX idx_metadata_image ON image_metadata (image_id)'));
          await m.createIndex(Index('idx_metadata_key', 'CREATE INDEX idx_metadata_key ON image_metadata (key)'));

          // Create indexes for equipment_profiles
          await m.createIndex(Index('idx_profiles_name', 'CREATE INDEX idx_profiles_name ON equipment_profiles (name)'));
          await m.createIndex(Index('idx_profiles_active', 'CREATE INDEX idx_profiles_active ON equipment_profiles (is_active)'));
        }

        // Version 3: Add foreign key cascade deletes and sequence checkpointing
        if (from < 3) {
          // Create sequence_checkpoints table
          await m.createTable(sequenceCheckpoints);

          // Recreate tables with cascade deletes
          // Note: SQLite requires recreating tables to modify foreign keys
          // Drift handles this automatically when detecting schema changes

          // The following changes are applied:
          // 1. CapturedImages.sessionId - CASCADE on delete
          // 2. CapturedImages.targetId - SET NULL on delete
          // 3. ImageMetadata.imageId - CASCADE on delete
          // 4. SequenceNodes.sequenceId - CASCADE on delete
          // 5. SequenceNodes.targetId - SET NULL on delete
          // 6. SequenceCheckpoints.sequenceId - CASCADE on delete

          // Drift will handle the recreation of these tables with updated foreign keys
        }

        // Version 4: Add weather settings table
        if (from < 4) {
          await m.createTable(weatherSettings);
        }

        // Version 5: Add cover_calibrator_id to equipment_profiles
        if (from < 5) {
          final hasCoverCalibratorId = await _columnExists(
            'equipment_profiles',
            'cover_calibrator_id',
          );
          if (!hasCoverCalibratorId) {
            await customStatement(
              'ALTER TABLE equipment_profiles ADD COLUMN cover_calibrator_id TEXT',
            );
          }
        }

        // Version 6: Add meridian_flip_overrides to equipment_profiles
        if (from < 6) {
          final hasMeridianFlipOverrides = await _columnExists(
            'equipment_profiles',
            'meridian_flip_overrides',
          );
          if (!hasMeridianFlipOverrides) {
            await customStatement(
              'ALTER TABLE equipment_profiles ADD COLUMN meridian_flip_overrides TEXT',
            );
          }
        }

        // Version 7: Add flat history table
        if (from < 7) {
          await m.createTable(flatHistory);
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_flat_history_profile ON flat_history (equipment_profile_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_flat_history_filter ON flat_history (filter_name)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_flat_history_timestamp ON flat_history (timestamp)',
          );
        }
      },
    );
  }

  Future<void> _insertDefaultSettings() async {
    await into(appSettings).insert(AppSettingsCompanion.insert(
      key: 'theme',
      value: 'dark',
    ));
    await into(appSettings).insert(AppSettingsCompanion.insert(
      key: 'default_image_directory',
      value: '',
    ));
    await into(appSettings).insert(AppSettingsCompanion.insert(
      key: 'auto_connect_equipment',
      value: 'false',
    ));
    await into(appSettings).insert(AppSettingsCompanion.insert(
      key: 'observer_latitude',
      value: '0.0',
    ));
    await into(appSettings).insert(AppSettingsCompanion.insert(
      key: 'observer_longitude',
      value: '0.0',
    ));
    await into(appSettings).insert(AppSettingsCompanion.insert(
      key: 'observer_elevation',
      value: '0.0',
    ));
  }

  Future<bool> _columnExists(String table, String column) async {
    final result = await customSelect(
      "PRAGMA table_info('$table')",
    ).get();
    return result.any((row) => row.data['name'] == column);
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'Nightshade', 'nightshade.db'));

    // Ensure directory exists
    await file.parent.create(recursive: true);

    return NativeDatabase.createInBackground(file);
  });
}
