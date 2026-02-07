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
import 'tables/tutorial_progress.dart';
import 'tables/polar_alignment_history.dart';
import 'tables/science.dart';
import 'daos/images_dao.dart';
import 'daos/equipment_profiles_dao.dart';
import 'daos/sessions_dao.dart';
import 'daos/sequences_dao.dart';
import 'daos/sequence_checkpoints_dao.dart';
import 'daos/targets_dao.dart';
import 'daos/settings_dao.dart';
import 'daos/weather_settings_dao.dart';
import 'daos/flat_history_dao.dart';
import 'daos/tutorial_progress_dao.dart';
import 'daos/polar_alignment_history_dao.dart';
import 'daos/science_dao.dart';

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
    TutorialProgress,
    PolarAlignmentHistory,
    ScienceSessionConfig,
    PhotometryMeasurements,
    FramePhotometricCalibration,
    TransparencySamples,
    PsfFieldTiles,
    ScienceFrameQualityMetrics,
    ScienceTileMetrics,
    AstrometryResidualVectors,
    MovingObjectCandidates,
    LineRatioProducts,
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
    TutorialProgressDao,
    PolarAlignmentHistoryDao,
    ScienceDao,
  ],
)
class NightshadeDatabase extends _$NightshadeDatabase {
  NightshadeDatabase() : super(_openConnection());

  /// For testing with a custom QueryExecutor
  NightshadeDatabase.forTesting(QueryExecutor e) : super(e);

  @override
  int get schemaVersion => 14;

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
          await m.createIndex(Index('idx_targets_name',
              'CREATE INDEX idx_targets_name ON targets (name)'));
          await m.createIndex(Index('idx_targets_catalog',
              'CREATE INDEX idx_targets_catalog ON targets (catalog_id)'));
          await m.createIndex(Index('idx_targets_priority',
              'CREATE INDEX idx_targets_priority ON targets (priority)'));
          await m.createIndex(Index('idx_targets_favorite',
              'CREATE INDEX idx_targets_favorite ON targets (is_favorite)'));
          await m.createIndex(Index('idx_targets_object_type',
              'CREATE INDEX idx_targets_object_type ON targets (object_type)'));

          // Create indexes for captured_images
          await m.createIndex(Index('idx_images_session',
              'CREATE INDEX idx_images_session ON captured_images (session_id)'));
          await m.createIndex(Index('idx_images_target',
              'CREATE INDEX idx_images_target ON captured_images (target_id)'));
          await m.createIndex(Index('idx_images_frame_type',
              'CREATE INDEX idx_images_frame_type ON captured_images (frame_type)'));
          await m.createIndex(Index('idx_images_captured_at',
              'CREATE INDEX idx_images_captured_at ON captured_images (captured_at)'));
          await m.createIndex(Index('idx_images_filter',
              'CREATE INDEX idx_images_filter ON captured_images (filter)'));
          await m.createIndex(Index('idx_images_accepted',
              'CREATE INDEX idx_images_accepted ON captured_images (is_accepted)'));
          await m.createIndex(Index('idx_images_session_frame',
              'CREATE INDEX idx_images_session_frame ON captured_images (session_id, frame_type)'));

          // Create indexes for imaging_sessions
          await m.createIndex(Index('idx_sessions_target',
              'CREATE INDEX idx_sessions_target ON imaging_sessions (target_id)'));
          await m.createIndex(Index('idx_sessions_profile',
              'CREATE INDEX idx_sessions_profile ON imaging_sessions (profile_id)'));
          await m.createIndex(Index('idx_sessions_start',
              'CREATE INDEX idx_sessions_start ON imaging_sessions (start_time)'));
          await m.createIndex(Index('idx_sessions_status',
              'CREATE INDEX idx_sessions_status ON imaging_sessions (status)'));

          // Create indexes for sequences
          await m.createIndex(Index('idx_sequences_name',
              'CREATE INDEX idx_sequences_name ON sequences (name)'));
          await m.createIndex(Index('idx_sequences_template',
              'CREATE INDEX idx_sequences_template ON sequences (is_template)'));
          await m.createIndex(Index('idx_sequences_updated',
              'CREATE INDEX idx_sequences_updated ON sequences (updated_at)'));

          // Create indexes for sequence_nodes
          await m.createIndex(Index('idx_nodes_sequence',
              'CREATE INDEX idx_nodes_sequence ON sequence_nodes (sequence_id)'));
          await m.createIndex(Index('idx_nodes_parent',
              'CREATE INDEX idx_nodes_parent ON sequence_nodes (parent_node_id)'));
          await m.createIndex(Index('idx_nodes_target',
              'CREATE INDEX idx_nodes_target ON sequence_nodes (target_id)'));
          await m.createIndex(Index('idx_nodes_type',
              'CREATE INDEX idx_nodes_type ON sequence_nodes (node_type)'));
          await m.createIndex(Index('idx_nodes_node_id',
              'CREATE INDEX idx_nodes_node_id ON sequence_nodes (node_id)'));

          // Create indexes for image_metadata
          await m.createIndex(Index('idx_metadata_image',
              'CREATE INDEX idx_metadata_image ON image_metadata (image_id)'));
          await m.createIndex(Index('idx_metadata_key',
              'CREATE INDEX idx_metadata_key ON image_metadata (key)'));

          // Create indexes for equipment_profiles
          await m.createIndex(Index('idx_profiles_name',
              'CREATE INDEX idx_profiles_name ON equipment_profiles (name)'));
          await m.createIndex(Index('idx_profiles_active',
              'CREATE INDEX idx_profiles_active ON equipment_profiles (is_active)'));
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

        // Version 8: Add Quick Start support columns to imaging_sessions
        if (from < 8) {
          final hasSequenceId = await _columnExists(
            'imaging_sessions',
            'sequence_id',
          );
          if (!hasSequenceId) {
            await customStatement(
              'ALTER TABLE imaging_sessions ADD COLUMN sequence_id INTEGER REFERENCES sequences(id)',
            );
          }

          final hasEquipmentSnapshot = await _columnExists(
            'imaging_sessions',
            'equipment_snapshot',
          );
          if (!hasEquipmentSnapshot) {
            await customStatement(
              'ALTER TABLE imaging_sessions ADD COLUMN equipment_snapshot TEXT',
            );
          }
        }

        // Version 9: Add tutorial progress table
        if (from < 9) {
          await m.createTable(tutorialProgress);
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_tutorial_progress_category ON tutorial_progress (category)',
          );
        }

        // Version 10: Add polar alignment history table
        if (from < 10) {
          await m.createTable(polarAlignmentHistory);
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_polar_history_profile ON polar_alignment_history (equipment_profile_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_polar_history_started ON polar_alignment_history (started_at)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_polar_history_completed ON polar_alignment_history (completed_at)',
          );

          final hasQualityScore =
              await _columnExists('captured_images', 'quality_score');
          if (!hasQualityScore) {
            await customStatement(
              'ALTER TABLE captured_images ADD COLUMN quality_score REAL',
            );
          }
        }

        // Version 11: Add user-friendly device names, telescope info, and profile customization to equipment_profiles
        if (from < 11) {
          // User-friendly device names
          final hasCameraName =
              await _columnExists('equipment_profiles', 'camera_name');
          if (!hasCameraName) {
            await customStatement(
              'ALTER TABLE equipment_profiles ADD COLUMN camera_name TEXT',
            );
          }
          final hasMountName =
              await _columnExists('equipment_profiles', 'mount_name');
          if (!hasMountName) {
            await customStatement(
              'ALTER TABLE equipment_profiles ADD COLUMN mount_name TEXT',
            );
          }
          final hasFocuserName =
              await _columnExists('equipment_profiles', 'focuser_name');
          if (!hasFocuserName) {
            await customStatement(
              'ALTER TABLE equipment_profiles ADD COLUMN focuser_name TEXT',
            );
          }
          final hasFilterWheelName =
              await _columnExists('equipment_profiles', 'filter_wheel_name');
          if (!hasFilterWheelName) {
            await customStatement(
              'ALTER TABLE equipment_profiles ADD COLUMN filter_wheel_name TEXT',
            );
          }
          final hasGuiderName =
              await _columnExists('equipment_profiles', 'guider_name');
          if (!hasGuiderName) {
            await customStatement(
              'ALTER TABLE equipment_profiles ADD COLUMN guider_name TEXT',
            );
          }
          final hasRotatorName =
              await _columnExists('equipment_profiles', 'rotator_name');
          if (!hasRotatorName) {
            await customStatement(
              'ALTER TABLE equipment_profiles ADD COLUMN rotator_name TEXT',
            );
          }

          // Telescope/OTA information
          final hasTelescopeName =
              await _columnExists('equipment_profiles', 'telescope_name');
          if (!hasTelescopeName) {
            await customStatement(
              'ALTER TABLE equipment_profiles ADD COLUMN telescope_name TEXT',
            );
          }
          final hasTelescopeFocalLength = await _columnExists(
              'equipment_profiles', 'telescope_focal_length');
          if (!hasTelescopeFocalLength) {
            await customStatement(
              'ALTER TABLE equipment_profiles ADD COLUMN telescope_focal_length REAL',
            );
          }
          final hasTelescopeAperture =
              await _columnExists('equipment_profiles', 'telescope_aperture');
          if (!hasTelescopeAperture) {
            await customStatement(
              'ALTER TABLE equipment_profiles ADD COLUMN telescope_aperture REAL',
            );
          }

          // Profile customization
          final hasProfileIcon =
              await _columnExists('equipment_profiles', 'profile_icon');
          if (!hasProfileIcon) {
            await customStatement(
              'ALTER TABLE equipment_profiles ADD COLUMN profile_icon TEXT',
            );
          }
          final hasProfileColor =
              await _columnExists('equipment_profiles', 'profile_color');
          if (!hasProfileColor) {
            await customStatement(
              'ALTER TABLE equipment_profiles ADD COLUMN profile_color INTEGER',
            );
          }
          final hasSortOrder =
              await _columnExists('equipment_profiles', 'sort_order');
          if (!hasSortOrder) {
            await customStatement(
              'ALTER TABLE equipment_profiles ADD COLUMN sort_order INTEGER DEFAULT 0',
            );
          }
          final hasIsDefault =
              await _columnExists('equipment_profiles', 'is_default');
          if (!hasIsDefault) {
            await customStatement(
              'ALTER TABLE equipment_profiles ADD COLUMN is_default INTEGER DEFAULT 0',
            );
          }
        }

        // Version 12: Add cool_on_connect to equipment_profiles
        if (from < 12) {
          final hasCoolOnConnect =
              await _columnExists('equipment_profiles', 'cool_on_connect');
          if (!hasCoolOnConnect) {
            await customStatement(
              'ALTER TABLE equipment_profiles ADD COLUMN cool_on_connect INTEGER NOT NULL DEFAULT 0',
            );
          }
        }

        // Version 13: Add science suite tables
        if (from < 13) {
          await m.createTable(scienceSessionConfig);
          await m.createTable(photometryMeasurements);
          await m.createTable(framePhotometricCalibration);
          await m.createTable(transparencySamples);
          await m.createTable(psfFieldTiles);
          await m.createTable(astrometryResidualVectors);
          await m.createTable(movingObjectCandidates);
          await m.createTable(lineRatioProducts);

          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_photometry_measurements_image ON photometry_measurements (captured_image_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_photometry_measurements_session ON photometry_measurements (session_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_photometry_measurements_timestamp ON photometry_measurements (timestamp)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_photometry_measurements_object ON photometry_measurements (object_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_frame_photometric_calibration_image ON frame_photometric_calibration (captured_image_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_frame_photometric_calibration_session ON frame_photometric_calibration (session_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_frame_photometric_calibration_timestamp ON frame_photometric_calibration (timestamp)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_frame_photometric_calibration_solver ON frame_photometric_calibration (solver_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_transparency_samples_image ON transparency_samples (captured_image_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_transparency_samples_session ON transparency_samples (session_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_transparency_samples_timestamp ON transparency_samples (timestamp)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_psf_field_tiles_image ON psf_field_tiles (captured_image_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_psf_field_tiles_session ON psf_field_tiles (session_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_psf_field_tiles_timestamp ON psf_field_tiles (timestamp)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_astrometry_residual_vectors_image ON astrometry_residual_vectors (captured_image_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_astrometry_residual_vectors_session ON astrometry_residual_vectors (session_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_astrometry_residual_vectors_timestamp ON astrometry_residual_vectors (timestamp)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_moving_object_candidates_image ON moving_object_candidates (captured_image_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_moving_object_candidates_session ON moving_object_candidates (session_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_moving_object_candidates_timestamp ON moving_object_candidates (timestamp)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_moving_object_candidates_object ON moving_object_candidates (candidate_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_line_ratio_products_session ON line_ratio_products (session_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_line_ratio_products_timestamp ON line_ratio_products (created_at)',
          );

          await customStatement(
            "INSERT OR IGNORE INTO app_settings (key, value) VALUES ('science.advanced_mode.enabled', 'false')",
          );
          await customStatement(
            "INSERT OR IGNORE INTO app_settings (key, value) VALUES ('science.overlay.enabled', 'true')",
          );
          await customStatement(
            "INSERT OR IGNORE INTO app_settings (key, value) VALUES ('science.feature.photometry', 'true')",
          );
          await customStatement(
            "INSERT OR IGNORE INTO app_settings (key, value) VALUES ('science.feature.photometric_calibration', 'true')",
          );
          await customStatement(
            "INSERT OR IGNORE INTO app_settings (key, value) VALUES ('science.feature.transparency', 'true')",
          );
          await customStatement(
            "INSERT OR IGNORE INTO app_settings (key, value) VALUES ('science.feature.psf_map', 'true')",
          );
          await customStatement(
            "INSERT OR IGNORE INTO app_settings (key, value) VALUES ('science.feature.astrometric_residuals', 'true')",
          );
          await customStatement(
            "INSERT OR IGNORE INTO app_settings (key, value) VALUES ('science.feature.moving_objects', 'false')",
          );
          await customStatement(
            "INSERT OR IGNORE INTO app_settings (key, value) VALUES ('science.feature.narrowband_ratios', 'false')",
          );
          await customStatement(
            "INSERT OR IGNORE INTO app_settings (key, value) VALUES ('science.retention.manual_purge_only', 'true')",
          );
          await customStatement(
            "INSERT OR IGNORE INTO app_settings (key, value) VALUES ('science.photometry.differential_active', 'false')",
          );
          await customStatement(
            "INSERT OR IGNORE INTO app_settings (key, value) VALUES ('science.photometry.target_anchor', '')",
          );
          await customStatement(
            "INSERT OR IGNORE INTO app_settings (key, value) VALUES ('science.photometry.comparison_anchors', '[]')",
          );
        }

        // Version 14: Add frame quality and tile metrics tables
        if (from < 14) {
          await m.createTable(scienceFrameQualityMetrics);
          await m.createTable(scienceTileMetrics);

          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_science_frame_quality_metrics_image ON science_frame_quality_metrics (captured_image_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_science_frame_quality_metrics_session_layer_timestamp ON science_frame_quality_metrics (session_id, processing_tier, timestamp)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_science_tile_metrics_session_layer_timestamp ON science_tile_metrics (session_id, layer_type, timestamp)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_science_tile_metrics_image_layer ON science_tile_metrics (captured_image_id, layer_type)',
          );

          await customStatement(
            "INSERT OR IGNORE INTO app_settings (key, value) VALUES ('science.feature.frame_quality_maps', 'true')",
          );
          await customStatement(
            "INSERT OR IGNORE INTO app_settings (key, value) VALUES ('science.feature.surface3d', 'true')",
          );
          await customStatement(
            "INSERT OR IGNORE INTO app_settings (key, value) VALUES ('science.overlay.opacity', '0.35')",
          );
          await customStatement(
            "INSERT OR IGNORE INTO app_settings (key, value) VALUES ('science.overlay.live_grid_rows', '12')",
          );
          await customStatement(
            "INSERT OR IGNORE INTO app_settings (key, value) VALUES ('science.overlay.live_grid_cols', '16')",
          );
          await customStatement(
            "INSERT OR IGNORE INTO app_settings (key, value) VALUES ('science.overlay.analysis_grid_rows', '24')",
          );
          await customStatement(
            "INSERT OR IGNORE INTO app_settings (key, value) VALUES ('science.overlay.analysis_grid_cols', '32')",
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
    await into(appSettings).insert(AppSettingsCompanion.insert(
      key: 'science.advanced_mode.enabled',
      value: 'false',
    ));
    await into(appSettings).insert(AppSettingsCompanion.insert(
      key: 'science.overlay.enabled',
      value: 'true',
    ));
    await into(appSettings).insert(AppSettingsCompanion.insert(
      key: 'science.feature.photometry',
      value: 'true',
    ));
    await into(appSettings).insert(AppSettingsCompanion.insert(
      key: 'science.feature.photometric_calibration',
      value: 'true',
    ));
    await into(appSettings).insert(AppSettingsCompanion.insert(
      key: 'science.feature.transparency',
      value: 'true',
    ));
    await into(appSettings).insert(AppSettingsCompanion.insert(
      key: 'science.feature.psf_map',
      value: 'true',
    ));
    await into(appSettings).insert(AppSettingsCompanion.insert(
      key: 'science.feature.astrometric_residuals',
      value: 'true',
    ));
    await into(appSettings).insert(AppSettingsCompanion.insert(
      key: 'science.feature.moving_objects',
      value: 'false',
    ));
    await into(appSettings).insert(AppSettingsCompanion.insert(
      key: 'science.feature.narrowband_ratios',
      value: 'false',
    ));
    await into(appSettings).insert(AppSettingsCompanion.insert(
      key: 'science.feature.frame_quality_maps',
      value: 'true',
    ));
    await into(appSettings).insert(AppSettingsCompanion.insert(
      key: 'science.feature.surface3d',
      value: 'true',
    ));
    await into(appSettings).insert(AppSettingsCompanion.insert(
      key: 'science.retention.manual_purge_only',
      value: 'true',
    ));
    await into(appSettings).insert(AppSettingsCompanion.insert(
      key: 'science.photometry.differential_active',
      value: 'false',
    ));
    await into(appSettings).insert(AppSettingsCompanion.insert(
      key: 'science.photometry.target_anchor',
      value: '',
    ));
    await into(appSettings).insert(AppSettingsCompanion.insert(
      key: 'science.photometry.comparison_anchors',
      value: '[]',
    ));
    await into(appSettings).insert(AppSettingsCompanion.insert(
      key: 'science.overlay.opacity',
      value: '0.35',
    ));
    await into(appSettings).insert(AppSettingsCompanion.insert(
      key: 'science.overlay.live_grid_rows',
      value: '12',
    ));
    await into(appSettings).insert(AppSettingsCompanion.insert(
      key: 'science.overlay.live_grid_cols',
      value: '16',
    ));
    await into(appSettings).insert(AppSettingsCompanion.insert(
      key: 'science.overlay.analysis_grid_rows',
      value: '24',
    ));
    await into(appSettings).insert(AppSettingsCompanion.insert(
      key: 'science.overlay.analysis_grid_cols',
      value: '32',
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
