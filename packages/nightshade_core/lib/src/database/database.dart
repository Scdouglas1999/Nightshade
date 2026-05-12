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
import 'tables/dark_library.dart';
import 'tables/observation_logs.dart';
import 'tables/observing_lists.dart';
import 'tables/sequence_runs.dart';
import 'tables/defect_map_table.dart';
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
import 'daos/dark_library_dao.dart';
import 'daos/observation_logs_dao.dart';
import 'daos/observing_lists_dao.dart';
import 'daos/sequence_runs_dao.dart';

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
    PhotometricTransforms,
    DarkLibrary,
    ObservationLogs,
    ObservingLists,
    ObservingListItems,
    SequenceRuns,
    DefectMaps,
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
    DarkLibraryDao,
    ObservationLogsDao,
    ObservingListsDao,
    SequenceRunsDao,
  ],
)
class NightshadeDatabase extends _$NightshadeDatabase {
  NightshadeDatabase() : super(_openConnection());

  /// For testing with a custom QueryExecutor
  NightshadeDatabase.forTesting(QueryExecutor e) : super(e);

  @override
  int get schemaVersion => 28;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
        await _createCustomIndexes();
        await _ensureDefaultSettings();
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

        // Version 3: Add sequence checkpointing table.
        // BUG (fixed in v18): The original v3 migration claimed Drift would
        // automatically recreate tables with updated FK constraints, but Drift
        // does NOT do that — SQLite requires explicit table recreation. The FK
        // cascade changes for captured_images, image_metadata, and
        // sequence_nodes were never applied to databases upgraded through v3.
        // Version 18 retroactively applies these FK fixes.
        if (from < 3) {
          await m.createTable(sequenceCheckpoints);
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

        // Version 15: Add default_centering_exposure to equipment_profiles
        if (from < 15) {
          final hasCenteringExposure = await _columnExists(
              'equipment_profiles', 'default_centering_exposure');
          if (!hasCenteringExposure) {
            await customStatement(
              'ALTER TABLE equipment_profiles ADD COLUMN default_centering_exposure REAL',
            );
          }
        }

        // Version 16: Fix FK constraints and polar_alignment_history column type
        // - imaging_sessions: profileId and targetId now have ON DELETE SET NULL
        // - flat_history: equipmentProfileId is now a proper FK to equipment_profiles
        // - polar_alignment_history: equipmentProfileId changed from TEXT to INTEGER
        if (from < 16) {
          // Recreate imaging_sessions with ON DELETE SET NULL FK constraints
          await customStatement('''
            CREATE TABLE imaging_sessions_new (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT,
              profile_id INTEGER REFERENCES equipment_profiles(id) ON DELETE SET NULL,
              target_id INTEGER REFERENCES targets(id) ON DELETE SET NULL,
              start_time INTEGER NOT NULL,
              end_time INTEGER,
              total_exposures INTEGER NOT NULL DEFAULT 0,
              successful_exposures INTEGER NOT NULL DEFAULT 0,
              failed_exposures INTEGER NOT NULL DEFAULT 0,
              total_integration_secs REAL NOT NULL DEFAULT 0.0,
              avg_temperature REAL,
              avg_humidity REAL,
              avg_seeing REAL,
              avg_hfr REAL,
              avg_guiding_rms REAL,
              autofocus_count INTEGER NOT NULL DEFAULT 0,
              notes TEXT,
              status TEXT NOT NULL DEFAULT 'completed',
              sequence_id INTEGER REFERENCES sequences(id),
              equipment_snapshot TEXT
            )
          ''');
          await customStatement('''
            INSERT INTO imaging_sessions_new
              SELECT * FROM imaging_sessions
          ''');
          await customStatement('DROP TABLE imaging_sessions');
          await customStatement(
              'ALTER TABLE imaging_sessions_new RENAME TO imaging_sessions');
          // Recreate indexes
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_sessions_target ON imaging_sessions (target_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_sessions_profile ON imaging_sessions (profile_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_sessions_start ON imaging_sessions (start_time)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_sessions_status ON imaging_sessions (status)',
          );

          // Recreate flat_history with proper FK reference
          await customStatement('''
            CREATE TABLE flat_history_new (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              equipment_profile_id INTEGER REFERENCES equipment_profiles(id) ON DELETE SET NULL,
              filter_name TEXT NOT NULL,
              exposure_time REAL NOT NULL,
              histogram_target REAL NOT NULL,
              actual_adu INTEGER NOT NULL,
              panel_brightness INTEGER,
              sky_adu_rate REAL,
              twilight_phase TEXT,
              gain INTEGER NOT NULL DEFAULT 0,
              binning INTEGER NOT NULL DEFAULT 1,
              timestamp INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
            )
          ''');
          await customStatement('''
            INSERT INTO flat_history_new
              SELECT * FROM flat_history
          ''');
          await customStatement('DROP TABLE flat_history');
          await customStatement(
              'ALTER TABLE flat_history_new RENAME TO flat_history');
          // Recreate indexes
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_flat_history_profile ON flat_history (equipment_profile_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_flat_history_filter ON flat_history (filter_name)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_flat_history_timestamp ON flat_history (timestamp)',
          );

          // Recreate polar_alignment_history with INTEGER equipment_profile_id
          // and proper FK reference (was TEXT, now INTEGER)
          await customStatement('''
            CREATE TABLE polar_alignment_history_new (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              equipment_profile_id INTEGER REFERENCES equipment_profiles(id) ON DELETE SET NULL,
              initial_azimuth_error REAL NOT NULL,
              initial_altitude_error REAL NOT NULL,
              initial_total_error REAL NOT NULL,
              final_azimuth_error REAL NOT NULL,
              final_altitude_error REAL NOT NULL,
              final_total_error REAL NOT NULL,
              started_at INTEGER NOT NULL,
              completed_at INTEGER NOT NULL,
              auto_completed INTEGER NOT NULL DEFAULT 0,
              is_north INTEGER NOT NULL DEFAULT 1,
              config_json TEXT NOT NULL
            )
          ''');
          // Migrate data, casting TEXT equipment_profile_id to INTEGER
          // Invalid text values will become NULL (CAST returns 0 for non-numeric text, so use CASE)
          await customStatement('''
            INSERT INTO polar_alignment_history_new
              (id, equipment_profile_id, initial_azimuth_error, initial_altitude_error,
               initial_total_error, final_azimuth_error, final_altitude_error,
               final_total_error, started_at, completed_at, auto_completed, is_north, config_json)
            SELECT
              id,
              CASE
                WHEN equipment_profile_id IS NULL THEN NULL
                WHEN TYPEOF(equipment_profile_id) = 'integer' THEN equipment_profile_id
                WHEN equipment_profile_id GLOB '[0-9]*' THEN CAST(equipment_profile_id AS INTEGER)
                ELSE NULL
              END,
              initial_azimuth_error, initial_altitude_error,
              initial_total_error, final_azimuth_error, final_altitude_error,
              final_total_error, started_at, completed_at, auto_completed, is_north, config_json
            FROM polar_alignment_history
          ''');
          await customStatement('DROP TABLE polar_alignment_history');
          await customStatement(
              'ALTER TABLE polar_alignment_history_new RENAME TO polar_alignment_history');
          // Recreate indexes
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_polar_history_profile ON polar_alignment_history (equipment_profile_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_polar_history_started ON polar_alignment_history (started_at)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_polar_history_completed ON polar_alignment_history (completed_at)',
          );
        }

        // Version 17: Add dark frame library table
        if (from < 17) {
          await m.createTable(darkLibrary);
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_dark_library_frame_type ON dark_library (frame_type)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_dark_library_exposure ON dark_library (exposure_time)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_dark_library_temperature ON dark_library (temperature)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_dark_library_gain ON dark_library (gain)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_dark_library_match ON dark_library (frame_type, exposure_time, gain, bin_x, bin_y)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_dark_library_created ON dark_library (created_at)',
          );

          // Add dark library default settings
          await customStatement(
            "INSERT OR IGNORE INTO app_settings (key, value) VALUES ('dark_library.auto_subtract', 'false')",
          );
          await customStatement(
            "INSERT OR IGNORE INTO app_settings (key, value) VALUES ('dark_library.temp_tolerance', '2.0')",
          );
        }

        // Version 18: Retroactively apply the FK cascade changes that
        // migration v3 promised but never executed, add composite index
        // on captured_images (session_id, captured_at), and recreate
        // sequence_nodes/image_metadata with proper cascade FKs.
        if (from < 18) {
          await transaction(() async {
            // ── 1. Recreate sequence_nodes with ON DELETE CASCADE on sequenceId ──
            await customStatement('''
            CREATE TABLE sequence_nodes_new (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              node_id TEXT NOT NULL,
              sequence_id INTEGER NOT NULL REFERENCES sequences(id) ON DELETE CASCADE,
              target_id INTEGER REFERENCES targets(id) ON DELETE SET NULL,
              node_type TEXT NOT NULL,
              specific_type TEXT NOT NULL,
              name TEXT NOT NULL,
              properties TEXT NOT NULL DEFAULT '{}',
              recovery_config TEXT,
              parent_node_id TEXT,
              order_index INTEGER NOT NULL DEFAULT 0,
              is_enabled INTEGER NOT NULL DEFAULT 1
            )
          ''');
            await customStatement('''
            INSERT INTO sequence_nodes_new
              SELECT * FROM sequence_nodes
          ''');
            await customStatement('DROP TABLE sequence_nodes');
            await customStatement(
                'ALTER TABLE sequence_nodes_new RENAME TO sequence_nodes');
            // Recreate indexes for sequence_nodes
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_nodes_sequence ON sequence_nodes (sequence_id)',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_nodes_parent ON sequence_nodes (parent_node_id)',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_nodes_target ON sequence_nodes (target_id)',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_nodes_type ON sequence_nodes (node_type)',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_nodes_node_id ON sequence_nodes (node_id)',
            );

            // ── 2. Recreate captured_images with ON DELETE CASCADE / SET NULL FKs ──
            // First, drop all child tables that reference captured_images so SQLite
            // allows us to drop the parent. We'll recreate them afterward.
            //
            // Save child table data into temp tables before dropping.
            await customStatement(
              'CREATE TEMP TABLE _tmp_image_metadata AS SELECT * FROM image_metadata',
            );
            await customStatement('DROP TABLE image_metadata');

            // Science child tables that reference captured_images:
            await customStatement(
              'CREATE TEMP TABLE _tmp_photometry_measurements AS SELECT * FROM photometry_measurements',
            );
            await customStatement('DROP TABLE photometry_measurements');

            await customStatement(
              'CREATE TEMP TABLE _tmp_frame_photometric_calibration AS SELECT * FROM frame_photometric_calibration',
            );
            await customStatement('DROP TABLE frame_photometric_calibration');

            await customStatement(
              'CREATE TEMP TABLE _tmp_transparency_samples AS SELECT * FROM transparency_samples',
            );
            await customStatement('DROP TABLE transparency_samples');

            await customStatement(
              'CREATE TEMP TABLE _tmp_psf_field_tiles AS SELECT * FROM psf_field_tiles',
            );
            await customStatement('DROP TABLE psf_field_tiles');

            await customStatement(
              'CREATE TEMP TABLE _tmp_science_frame_quality_metrics AS SELECT * FROM science_frame_quality_metrics',
            );
            await customStatement('DROP TABLE science_frame_quality_metrics');

            await customStatement(
              'CREATE TEMP TABLE _tmp_science_tile_metrics AS SELECT * FROM science_tile_metrics',
            );
            await customStatement('DROP TABLE science_tile_metrics');

            await customStatement(
              'CREATE TEMP TABLE _tmp_astrometry_residual_vectors AS SELECT * FROM astrometry_residual_vectors',
            );
            await customStatement('DROP TABLE astrometry_residual_vectors');

            await customStatement(
              'CREATE TEMP TABLE _tmp_moving_object_candidates AS SELECT * FROM moving_object_candidates',
            );
            await customStatement('DROP TABLE moving_object_candidates');

            await customStatement(
              'CREATE TEMP TABLE _tmp_line_ratio_products AS SELECT * FROM line_ratio_products',
            );
            await customStatement('DROP TABLE line_ratio_products');

            // Now recreate captured_images with correct FK constraints
            await customStatement('''
            CREATE TABLE captured_images_new (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              file_path TEXT NOT NULL,
              file_name TEXT NOT NULL,
              file_format TEXT NOT NULL DEFAULT 'fits',
              file_size INTEGER,
              session_id INTEGER REFERENCES imaging_sessions(id) ON DELETE CASCADE,
              target_id INTEGER REFERENCES targets(id) ON DELETE SET NULL,
              frame_type TEXT NOT NULL DEFAULT 'light',
              exposure_duration REAL NOT NULL,
              gain INTEGER,
              "offset" INTEGER,
              bin_x INTEGER NOT NULL DEFAULT 1,
              bin_y INTEGER NOT NULL DEFAULT 1,
              filter TEXT,
              sensor_temp REAL,
              cooler_power REAL,
              hfr REAL,
              star_count INTEGER,
              background REAL,
              noise REAL,
              quality_score REAL,
              guiding_rms_ra REAL,
              guiding_rms_dec REAL,
              guiding_rms_total REAL,
              mount_ra REAL,
              mount_dec REAL,
              mount_altitude REAL,
              mount_azimuth REAL,
              pier_side TEXT,
              focuser_position INTEGER,
              focuser_temp REAL,
              rotator_angle REAL,
              is_plate_solved INTEGER NOT NULL DEFAULT 0,
              solved_ra REAL,
              solved_dec REAL,
              solved_rotation REAL,
              solved_pixel_scale REAL,
              captured_at INTEGER NOT NULL,
              created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
              is_accepted INTEGER NOT NULL DEFAULT 1,
              rejection_reason TEXT
            )
          ''');
            await customStatement('''
            INSERT INTO captured_images_new
              SELECT * FROM captured_images
          ''');
            await customStatement('DROP TABLE captured_images');
            await customStatement(
                'ALTER TABLE captured_images_new RENAME TO captured_images');

            // Recreate indexes for captured_images
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_images_session ON captured_images (session_id)',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_images_target ON captured_images (target_id)',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_images_frame_type ON captured_images (frame_type)',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_images_captured_at ON captured_images (captured_at)',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_images_filter ON captured_images (filter)',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_images_accepted ON captured_images (is_accepted)',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_images_session_frame ON captured_images (session_id, frame_type)',
            );
            // New composite index for session queries ordered by capture time
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_images_session_captured_at ON captured_images (session_id, captured_at)',
            );

            // ── 3. Recreate image_metadata with ON DELETE CASCADE FK ──
            await customStatement('''
            CREATE TABLE image_metadata (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              image_id INTEGER NOT NULL REFERENCES captured_images(id) ON DELETE CASCADE,
              "key" TEXT NOT NULL,
              value TEXT NOT NULL,
              comment TEXT
            )
          ''');
            await customStatement('''
            INSERT INTO image_metadata
              SELECT * FROM _tmp_image_metadata
          ''');
            await customStatement('DROP TABLE _tmp_image_metadata');
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_metadata_image ON image_metadata (image_id)',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_metadata_key ON image_metadata ("key")',
            );

            // ── 4. Recreate science child tables that reference captured_images ──

            // photometry_measurements
            await m.createTable(photometryMeasurements);
            await customStatement('''
            INSERT INTO photometry_measurements
              SELECT * FROM _tmp_photometry_measurements
          ''');
            await customStatement('DROP TABLE _tmp_photometry_measurements');
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

            // frame_photometric_calibration
            await m.createTable(framePhotometricCalibration);
            await customStatement('''
            INSERT INTO frame_photometric_calibration
              SELECT * FROM _tmp_frame_photometric_calibration
          ''');
            await customStatement(
                'DROP TABLE _tmp_frame_photometric_calibration');
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

            // transparency_samples
            await m.createTable(transparencySamples);
            await customStatement('''
            INSERT INTO transparency_samples
              SELECT * FROM _tmp_transparency_samples
          ''');
            await customStatement('DROP TABLE _tmp_transparency_samples');
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_transparency_samples_image ON transparency_samples (captured_image_id)',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_transparency_samples_session ON transparency_samples (session_id)',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_transparency_samples_timestamp ON transparency_samples (timestamp)',
            );

            // psf_field_tiles
            await m.createTable(psfFieldTiles);
            await customStatement('''
            INSERT INTO psf_field_tiles
              SELECT * FROM _tmp_psf_field_tiles
          ''');
            await customStatement('DROP TABLE _tmp_psf_field_tiles');
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_psf_field_tiles_image ON psf_field_tiles (captured_image_id)',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_psf_field_tiles_session ON psf_field_tiles (session_id)',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_psf_field_tiles_timestamp ON psf_field_tiles (timestamp)',
            );

            // science_frame_quality_metrics
            await m.createTable(scienceFrameQualityMetrics);
            await customStatement('''
            INSERT INTO science_frame_quality_metrics
              SELECT * FROM _tmp_science_frame_quality_metrics
          ''');
            await customStatement(
                'DROP TABLE _tmp_science_frame_quality_metrics');
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_science_frame_quality_metrics_image ON science_frame_quality_metrics (captured_image_id)',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_science_frame_quality_metrics_session_layer_timestamp ON science_frame_quality_metrics (session_id, processing_tier, timestamp)',
            );

            // science_tile_metrics
            await m.createTable(scienceTileMetrics);
            await customStatement('''
            INSERT INTO science_tile_metrics
              SELECT * FROM _tmp_science_tile_metrics
          ''');
            await customStatement('DROP TABLE _tmp_science_tile_metrics');
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_science_tile_metrics_session_layer_timestamp ON science_tile_metrics (session_id, layer_type, timestamp)',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_science_tile_metrics_image_layer ON science_tile_metrics (captured_image_id, layer_type)',
            );

            // astrometry_residual_vectors
            await m.createTable(astrometryResidualVectors);
            await customStatement('''
            INSERT INTO astrometry_residual_vectors
              SELECT * FROM _tmp_astrometry_residual_vectors
          ''');
            await customStatement(
                'DROP TABLE _tmp_astrometry_residual_vectors');
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_astrometry_residual_vectors_image ON astrometry_residual_vectors (captured_image_id)',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_astrometry_residual_vectors_session ON astrometry_residual_vectors (session_id)',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_astrometry_residual_vectors_timestamp ON astrometry_residual_vectors (timestamp)',
            );

            // moving_object_candidates
            await m.createTable(movingObjectCandidates);
            await customStatement('''
            INSERT INTO moving_object_candidates
              SELECT * FROM _tmp_moving_object_candidates
          ''');
            await customStatement('DROP TABLE _tmp_moving_object_candidates');
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

            // line_ratio_products
            await m.createTable(lineRatioProducts);
            await customStatement('''
            INSERT INTO line_ratio_products
              SELECT * FROM _tmp_line_ratio_products
          ''');
            await customStatement('DROP TABLE _tmp_line_ratio_products');
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_line_ratio_products_session ON line_ratio_products (session_id)',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_line_ratio_products_timestamp ON line_ratio_products (created_at)',
            );
          });
        }

        if (from < 19) {
          if (!await _columnExists(
              'weather_settings', 'max_humidity_percent')) {
            await customStatement(
              'ALTER TABLE weather_settings ADD COLUMN max_humidity_percent REAL NOT NULL DEFAULT 90.0',
            );
          }
          if (!await _columnExists('weather_settings', 'max_wind_speed_kph')) {
            await customStatement(
              'ALTER TABLE weather_settings ADD COLUMN max_wind_speed_kph REAL NOT NULL DEFAULT 30.0',
            );
          }
          if (!await _columnExists(
              'weather_settings', 'max_cloud_cover_percent')) {
            await customStatement(
              'ALTER TABLE weather_settings ADD COLUMN max_cloud_cover_percent REAL NOT NULL DEFAULT 80.0',
            );
          }
        }

        if (from < 20) {
          if (!await _columnExists('targets', 'goal_integration_secs')) {
            await customStatement(
              'ALTER TABLE targets ADD COLUMN goal_integration_secs REAL NOT NULL DEFAULT 0.0',
            );
          }
        }

        if (from < 21) {
          await _dedupeScienceSessionConfigRows();
          await _normalizeActiveProfiles();
          await _recreateImagingSessionsForSequenceDeleteBehavior();
          await _recreatePolarAlignmentHistoryForCascadeDelete();
        }

        if (from < 22) {
          await _normalizeEquipmentProfileOptics();
        }

        // Version 23: Add observation logs table
        // NOTE: This migration block must remain even though we're now at v24+.
        // Users upgrading from <23 still need to create observation_logs.
        if (from < 23) {
          await m.createTable(observationLogs);
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_obs_logs_timestamp ON observation_logs (timestamp)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_obs_logs_object_name ON observation_logs (object_name)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_obs_logs_catalog_id ON observation_logs (catalog_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_obs_logs_rating ON observation_logs (rating)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_obs_logs_profile ON observation_logs (equipment_profile_id)',
          );
        }

        // Version 24: Add observing lists tables
        if (from < 24) {
          await m.createTable(observingLists);
          await m.createTable(observingListItems);
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_observing_lists_name ON observing_lists (name)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_observing_lists_sort_order ON observing_lists (sort_order)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_observing_list_items_list ON observing_list_items (list_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_observing_list_items_catalog ON observing_list_items (catalog_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_observing_list_items_sort ON observing_list_items (list_id, sort_order)',
          );
        }

        // Version 25: Add sequence execution history table
        if (from < 25) {
          await m.createTable(sequenceRuns);
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_sequence_runs_sequence ON sequence_runs (sequence_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_sequence_runs_started ON sequence_runs (started_at)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_sequence_runs_status ON sequence_runs (status)',
          );
        }

        // Version 26: Add photometric transformation coefficients table
        // and standard_magnitude column to photometry_measurements
        if (from < 26) {
          await m.createTable(photometricTransforms);
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_photometric_transforms_filter ON photometric_transforms (filter_name)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_photometric_transforms_date ON photometric_transforms (date_computed)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_photometric_transforms_profile ON photometric_transforms (equipment_profile_id)',
          );

          if (!await _columnExists(
              'photometry_measurements', 'standard_magnitude')) {
            await customStatement(
              'ALTER TABLE photometry_measurements ADD COLUMN standard_magnitude REAL',
            );
          }
        }

        // Version 27: Dynamic scheduler tables (W6-SCHED). The tables are
        // intentionally managed with raw CREATE TABLE statements rather
        // than @DriftDatabase entries so they can land without an FRB/
        // drift codegen pass. The corresponding services do raw SQL
        // through customSelect/customStatement.
        if (from < 27) {
          await customStatement(
            'CREATE TABLE IF NOT EXISTS integration_goals ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT,'
            'target_id INTEGER NOT NULL REFERENCES targets(id) ON DELETE CASCADE,'
            'filter TEXT NOT NULL,'
            'exposure_seconds REAL NOT NULL,'
            'frame_count INTEGER NOT NULL,'
            'priority INTEGER NOT NULL DEFAULT 5,'
            'created_at INTEGER NOT NULL,'
            'UNIQUE(target_id, filter, exposure_seconds))',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_integration_goals_target '
            'ON integration_goals (target_id)',
          );
          await customStatement(
            'CREATE TABLE IF NOT EXISTS target_constraints ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT,'
            'target_id INTEGER NOT NULL REFERENCES targets(id) ON DELETE CASCADE,'
            'kind TEXT NOT NULL,'
            'payload_json TEXT NOT NULL,'
            'enabled INTEGER NOT NULL DEFAULT 1)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_target_constraints_target '
            'ON target_constraints (target_id)',
          );
          await customStatement(
            'CREATE TABLE IF NOT EXISTS horizon_profiles ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT,'
            'name TEXT NOT NULL,'
            'samples_json TEXT NOT NULL)',
          );
        }

        // Version 28: Defect map table for bad-pixel cosmetic correction (W6-DEFECT).
        if (from < 28) {
          await m.createTable(defectMaps);
          await customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_defect_maps_lookup '
            'ON defect_maps (camera_id, width, height, temperature_bucket_decicelsius)',
          );
        }

        await _ensureDefaultSettings();
        await _createCustomIndexes();
      },
    );
  }

  Future<void> _createCustomIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sessions_sequence ON imaging_sessions (sequence_id)',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_science_session_config_session_unique '
      'ON science_session_config (session_id) WHERE session_id IS NOT NULL',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_single_active '
      'ON equipment_profiles (is_active) WHERE is_active = 1',
    );
  }

  Future<void> _dedupeScienceSessionConfigRows() async {
    await customStatement('''
      DELETE FROM science_session_config
      WHERE session_id IS NOT NULL
        AND EXISTS (
          SELECT 1
          FROM science_session_config newer
          WHERE newer.session_id = science_session_config.session_id
            AND (
              newer.updated_at > science_session_config.updated_at
              OR (
                newer.updated_at = science_session_config.updated_at
                AND newer.id > science_session_config.id
              )
            )
        )
    ''');
  }

  Future<void> _normalizeActiveProfiles() async {
    await customStatement('''
      UPDATE equipment_profiles
      SET is_active = CASE
        WHEN id = (
          SELECT id
          FROM equipment_profiles
          WHERE is_active = 1
          ORDER BY updated_at DESC, id DESC
          LIMIT 1
        ) THEN 1
        ELSE 0
      END
      WHERE is_active = 1
    ''');
  }

  Future<void> _recreateImagingSessionsForSequenceDeleteBehavior() async {
    await customStatement('''
      CREATE TABLE imaging_sessions_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        profile_id INTEGER REFERENCES equipment_profiles(id) ON DELETE SET NULL,
        target_id INTEGER REFERENCES targets(id) ON DELETE SET NULL,
        start_time INTEGER NOT NULL,
        end_time INTEGER,
        total_exposures INTEGER NOT NULL DEFAULT 0,
        successful_exposures INTEGER NOT NULL DEFAULT 0,
        failed_exposures INTEGER NOT NULL DEFAULT 0,
        total_integration_secs REAL NOT NULL DEFAULT 0.0,
        avg_temperature REAL,
        avg_humidity REAL,
        avg_seeing REAL,
        avg_hfr REAL,
        avg_guiding_rms REAL,
        autofocus_count INTEGER NOT NULL DEFAULT 0,
        notes TEXT,
        status TEXT NOT NULL DEFAULT 'completed',
        sequence_id INTEGER REFERENCES sequences(id) ON DELETE SET NULL,
        equipment_snapshot TEXT
      )
    ''');
    await customStatement('''
      INSERT INTO imaging_sessions_new
      SELECT
        id, name, profile_id, target_id, start_time, end_time,
        total_exposures, successful_exposures, failed_exposures,
        total_integration_secs, avg_temperature, avg_humidity, avg_seeing,
        avg_hfr, avg_guiding_rms, autofocus_count, notes, status,
        sequence_id, equipment_snapshot
      FROM imaging_sessions
    ''');
    await customStatement('DROP TABLE imaging_sessions');
    await customStatement(
      'ALTER TABLE imaging_sessions_new RENAME TO imaging_sessions',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sessions_target ON imaging_sessions (target_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sessions_profile ON imaging_sessions (profile_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sessions_start ON imaging_sessions (start_time)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sessions_status ON imaging_sessions (status)',
    );
  }

  Future<void> _recreatePolarAlignmentHistoryForCascadeDelete() async {
    await customStatement('''
      CREATE TABLE polar_alignment_history_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        equipment_profile_id INTEGER REFERENCES equipment_profiles(id) ON DELETE CASCADE,
        initial_azimuth_error REAL NOT NULL,
        initial_altitude_error REAL NOT NULL,
        initial_total_error REAL NOT NULL,
        final_azimuth_error REAL NOT NULL,
        final_altitude_error REAL NOT NULL,
        final_total_error REAL NOT NULL,
        started_at INTEGER NOT NULL,
        completed_at INTEGER NOT NULL,
        auto_completed INTEGER NOT NULL DEFAULT 0,
        is_north INTEGER NOT NULL DEFAULT 1,
        config_json TEXT NOT NULL
      )
    ''');
    await customStatement('''
      INSERT INTO polar_alignment_history_new
      SELECT
        id, equipment_profile_id, initial_azimuth_error, initial_altitude_error,
        initial_total_error, final_azimuth_error, final_altitude_error,
        final_total_error, started_at, completed_at, auto_completed,
        is_north, config_json
      FROM polar_alignment_history
    ''');
    await customStatement('DROP TABLE polar_alignment_history');
    await customStatement(
      'ALTER TABLE polar_alignment_history_new RENAME TO polar_alignment_history',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_polar_history_profile ON polar_alignment_history (equipment_profile_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_polar_history_started ON polar_alignment_history (started_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_polar_history_completed ON polar_alignment_history (completed_at)',
    );
  }

  Future<void> _ensureDefaultSettings() async {
    for (final entry in _defaultSettings.entries) {
      await customStatement(
        'INSERT INTO app_settings (key, value) VALUES (?, ?) '
        'ON CONFLICT(key) DO NOTHING',
        [entry.key, entry.value],
      );
    }
  }

  Future<void> _normalizeEquipmentProfileOptics() async {
    await customStatement('''
      UPDATE equipment_profiles
      SET
        telescope_focal_length = CASE
          WHEN COALESCE(telescope_focal_length, 0) <= 0 AND focal_length > 0
            THEN focal_length
          ELSE telescope_focal_length
        END,
        telescope_aperture = CASE
          WHEN COALESCE(telescope_aperture, 0) <= 0 AND aperture > 0
            THEN aperture
          ELSE telescope_aperture
        END,
        focal_length = CASE
          WHEN focal_length <= 0 AND COALESCE(telescope_focal_length, 0) > 0
            THEN telescope_focal_length
          ELSE focal_length
        END,
        aperture = CASE
          WHEN aperture <= 0 AND COALESCE(telescope_aperture, 0) > 0
            THEN telescope_aperture
          ELSE aperture
        END
    ''');
  }

  Future<bool> _columnExists(String table, String column) async {
    final result = await customSelect(
      "PRAGMA table_info('$table')",
    ).get();
    return result.any((row) => row.data['name'] == column);
  }
}

const Map<String, String> _defaultSettings = {
  'theme': 'dark',
  'language': 'en',
  'accent_color': '#6366F1',
  'font_size': 'Medium',
  'ui_scale': 'Auto',
  'sidebar_collapsed': 'false',
  'start_minimized': 'false',
  'auto_connect_equipment': 'true',
  'auto_save_sequences': 'true',
  'confirm_before_closing': 'true',
  'auto_discover_on_launch': 'true',
  'observer_latitude': '0.0',
  'observer_longitude': '0.0',
  'observer_elevation': '0.0',
  'timezone': 'UTC',
  'use_system_time': 'true',
  'image_format': 'FITS',
  'file_naming_pattern': r'$TARGET_$FILTER_$DATE_$SEQ',
  'bit_depth': '16-bit',
  'plate_solver': 'ASTAP',
  'astap_path': '',
  'astrometry_path': '',
  'plate_solve_timeout': '60',
  'plate_solve_search_radius': '30.0',
  'blind_solve': 'false',
  'phd2_path': '',
  'phd2_host': 'localhost',
  'phd2_port': '4400',
  'notifications_enabled': 'true',
  'discord_webhook': '',
  'pushover_key': '',
  'pushover_user': '',
  'notify_on_sequence_complete': 'true',
  'notify_on_error': 'true',
  'notify_on_meridian_flip': 'false',
  'sound_enabled': 'true',
  'default_image_directory': '',
  'image_output_path': '',
  'sequences_path': '',
  'database_path': '',
  'logs_path': '',
  'indi_server_host': 'localhost',
  'indi_server_port': '7624',
  'indi_auto_connect': 'false',
  'alpaca_server_host': 'localhost',
  'alpaca_server_port': '11111',
  'alpaca_auto_discover': 'false',
  'use_native_execution': 'true',
  'use_simulation_mode': 'false',
  'web_server_enabled': 'false',
  'web_server_port': '8080',
  'cooling_behavior': 'On Connect',
  'default_gain': '100',
  'default_offset': '50',
  'enable_meridian_flip': 'true',
  'temp_compensation': 'true',
  'temp_coefficient': '-12.0',
  'backlash_compensation': '0',
  'dither_scale': 'Medium',
  'settle_threshold': '0.5',
  'settle_timeout': '30',
  'park_on_unsafe_weather': 'true',
  'park_before_dawn': 'true',
  'meridian_flip_minutes': '5',
  'auto_focus_on_filter_change': 'true',
  'use_filter_focus_offsets': 'true',
  'auto_focus_every_minutes': '60',
  'dither_enabled': 'true',
  'dither_every_frames': '3',
  'safety_fail_mode': 'failClosed',
  'af_method': 'Star HFR',
  'af_curve_fitting': 'Hyperbolic',
  'af_step_size': '50',
  'af_exposure_time': '4.0',
  'af_initial_offset_steps': '4',
  'af_number_of_attempts': '1',
  'af_use_brightest_n_stars': '0',
  'af_outer_crop_ratio': '1.0',
  'af_inner_crop_ratio': '0.0',
  'af_binning': '1',
  'af_r_squared_threshold': '0.7',
  'af_disable_guiding': 'false',
  'af_focuser_settle_time_ms': '500',
  'af_exposures_per_point': '1',
  'af_backlash_comp_method': 'Overshoot',
  'af_backlash_in': '350',
  'af_backlash_out': '0',
  'af_autofocus_filter_name': '',
  'af_filter_settings': '{}',
  'science.advanced_mode.enabled': 'false',
  'science.overlay.enabled': 'true',
  'science.feature.photometry': 'true',
  'science.feature.photometric_calibration': 'true',
  'science.feature.transparency': 'true',
  'science.feature.psf_map': 'true',
  'science.feature.astrometric_residuals': 'true',
  'science.feature.moving_objects': 'false',
  'science.feature.narrowband_ratios': 'false',
  'science.feature.frame_quality_maps': 'true',
  'science.feature.surface3d': 'true',
  'science.retention.manual_purge_only': 'true',
  'science.photometry.differential_active': 'false',
  'science.photometry.target_anchor': '',
  'science.photometry.comparison_anchors': '[]',
  'science.overlay.opacity': '0.35',
  'science.overlay.live_grid_rows': '12',
  'science.overlay.live_grid_cols': '16',
  'science.overlay.analysis_grid_rows': '24',
  'science.overlay.analysis_grid_cols': '32',
  'dark_library.auto_subtract': 'false',
  'dark_library.temp_tolerance': '2.0',
};

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'Nightshade', 'nightshade.db'));

    // Ensure directory exists
    await file.parent.create(recursive: true);

    return NativeDatabase.createInBackground(file);
  });
}
