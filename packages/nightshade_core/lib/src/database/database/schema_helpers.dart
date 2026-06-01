part of '../database.dart';

extension _NightshadeDatabaseSchemaHelpers on NightshadeDatabase {
  /// Create the v31 `focus_models` table + its indexes. Called from both
  /// `onCreate` (fresh installs run `m.createAll()` which already covers
  /// the Drift-declared table) and `onUpgrade` (for in-place migrations).
  ///
  /// We use raw DDL with `IF NOT EXISTS` to make this idempotent — drift's
  /// `createTable` is happy to fail if called twice, and we explicitly want
  /// the migration path to be re-runnable in case the prior run aborted.
  Future<void> _createFocusModelsTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS focus_models (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL,
        equipment_profile_id INTEGER REFERENCES equipment_profiles(id) ON DELETE SET NULL,
        filter_name TEXT NOT NULL,
        filter_index INTEGER,
        temperature_compensation_slope REAL NOT NULL,
        focus_offset_relative_to_lum INTEGER NOT NULL DEFAULT 0,
        intercept_at_reference_temp INTEGER NOT NULL,
        reference_temp_celsius REAL NOT NULL DEFAULT 10.0,
        last_trained_at INTEGER NOT NULL,
        training_run_count INTEGER NOT NULL DEFAULT 0,
        confidence_score REAL NOT NULL DEFAULT 0.0,
        last_used_at INTEGER,
        training_samples_json TEXT NOT NULL DEFAULT '[]',
        max_training_samples INTEGER NOT NULL DEFAULT 50,
        consecutive_bad_predictions INTEGER NOT NULL DEFAULT 0,
        accumulated_drift_steps INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_focus_models_profile '
      'ON focus_models (equipment_profile_id)',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_focus_models_profile_filter '
      'ON focus_models (equipment_profile_id, filter_name)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_focus_models_last_used '
      'ON focus_models (last_used_at)',
    );
  }

  /// Wave 6 Thumbnails (v30) — add producing-node provenance columns to
  /// `captured_images` if missing. Lives here (called from both
  /// `onCreate` and `onUpgrade`) because the columns are NOT declared on
  /// the Drift `CapturedImages` table class — same convention as the
  /// raw-DDL `notes_journal` / `defect_maps` tables — so a fresh install
  /// would otherwise skip them entirely after `m.createAll()`.
  /// Create the v34 `guide_rms_history` table + its lookup index.
  ///
  /// Drift creates the table on fresh installs through `m.createAll()`, but
  /// this helper is intentionally idempotent so upgrades and fresh-install
  /// index setup share the same schema path.
  Future<void> _createFrameForensicsTable() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS frame_forensics ('
      'id TEXT PRIMARY KEY NOT NULL,'
      'captured_image_id INTEGER REFERENCES captured_images(id) ON DELETE CASCADE,'
      'session_id TEXT,'
      'sequence_run_id INTEGER,'
      'node_id TEXT,'
      'frame_index INTEGER NOT NULL,'
      'total_frames INTEGER NOT NULL,'
      'reject_path TEXT NOT NULL,'
      'reason TEXT NOT NULL,'
      'likely_cause TEXT NOT NULL DEFAULT \'unknown\','
      'evidence_json TEXT NOT NULL DEFAULT \'[]\','
      'environment_json TEXT NOT NULL DEFAULT \'{}\','
      'hfr REAL,'
      'eccentricity REAL,'
      'star_count INTEGER,'
      'created_at INTEGER NOT NULL)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_frame_forensics_session '
      'ON frame_forensics (session_id, created_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_frame_forensics_run '
      'ON frame_forensics (sequence_run_id, created_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_frame_forensics_cause '
      'ON frame_forensics (likely_cause, created_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_frame_forensics_image '
      'ON frame_forensics (captured_image_id)',
    );
  }

  /// Create the v38 `stacked_results` table + its lookup indexes
  /// (Stack-and-Share Loop, C3).
  ///
  /// Raw DDL with `IF NOT EXISTS` keeps this idempotent so it can be safely run
  /// from both `onCreate` (fresh installs) and the v38 `onUpgrade` branch, and
  /// re-run if a prior migration aborted. `StackedResultsDao` is a plain class
  /// that reads/writes this table through `customSelect`/`customStatement`,
  /// matching the convention used for `frame_forensics` and `notes_journal`.
  ///
  /// Column nullability mirrors the [StackAndShareResult] model: `session_id`,
  /// `target_id`, `target_name`, `avg_alignment_residual`, `avg_hfr`, `filter`,
  /// and `exported_image_path` are optional, while the integration dimensions,
  /// frame counts, integration time, and creation timestamp are always present.
  /// The v39 colour-provenance columns (`is_color`, `channels`) are NOT NULL
  /// with mono defaults; see the v39 `onUpgrade` branch for the in-place ALTER
  /// that retrofits them onto pre-v39 databases.
  Future<void> _createStackedResultsTable() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS stacked_results('
      'id INTEGER PRIMARY KEY AUTOINCREMENT,'
      'session_id INTEGER,'
      'target_id INTEGER,'
      'target_name TEXT,'
      'width INTEGER NOT NULL,'
      'height INTEGER NOT NULL,'
      'frames_stacked INTEGER NOT NULL,'
      'frames_attempted INTEGER NOT NULL,'
      'integration_secs REAL NOT NULL,'
      'avg_alignment_residual REAL,'
      'avg_hfr REAL,'
      'filter TEXT,'
      // v39 (OSC / Color Stacking): colour provenance. `is_color` is a 0/1
      // boolean and `channels` is 1 (mono) or 3 (interleaved RGB). Both carry
      // NOT NULL DEFAULTs matching the [StackAndShareResult] model so the
      // upgrade ALTER and this fresh-install path stay in lock-step.
      'is_color INTEGER NOT NULL DEFAULT 0,'
      'channels INTEGER NOT NULL DEFAULT 1,'
      'exported_image_path TEXT,'
      'created_at INTEGER NOT NULL)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_stacked_results_session '
      'ON stacked_results(session_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_stacked_results_target '
      'ON stacked_results(target_id)',
    );
  }

  /// Create the v40 `projects` + `project_targets` tables (and their indexes)
  /// for the multi-night planner. Called from both `onCreate` (fresh installs)
  /// and the `if (from < 40)` `onUpgrade` branch (in-place migrations).
  ///
  /// These are raw-DDL tables (the dominant v27+ scheduler-stack convention)
  /// rather than Drift-declared tables; see
  /// `tables/project_table.dart` for the canonical schema documentation and
  /// `services/planning/project_service.dart`'s `ProjectService` for the
  /// read/write service.
  ///
  /// Every statement is `CREATE ... IF NOT EXISTS` so the helper is idempotent
  /// and the migration is re-runnable if a prior run aborted mid-flight. The
  /// `ON DELETE CASCADE` foreign keys mirror `integration_goals` /
  /// `target_constraints`; foreign-key enforcement is already enabled in
  /// `beforeOpen` (`PRAGMA foreign_keys = ON`), so deleting a project or a
  /// target tears down the corresponding `project_targets` rows automatically.
  Future<void> _createProjectsTables() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS projects('
      'id INTEGER PRIMARY KEY AUTOINCREMENT,'
      'name TEXT NOT NULL,'
      'description TEXT,'
      'color_argb INTEGER,'
      'created_at INTEGER NOT NULL,'
      'updated_at INTEGER NOT NULL)',
    );
    await customStatement(
      'CREATE TABLE IF NOT EXISTS project_targets('
      'id INTEGER PRIMARY KEY AUTOINCREMENT,'
      'project_id INTEGER NOT NULL '
      'REFERENCES projects(id) ON DELETE CASCADE,'
      'target_id INTEGER NOT NULL '
      'REFERENCES targets(id) ON DELETE CASCADE,'
      'priority_override INTEGER,'
      'added_at INTEGER NOT NULL,'
      'UNIQUE(project_id, target_id))',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_project_targets_project '
      'ON project_targets (project_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_project_targets_target '
      'ON project_targets (target_id)',
    );
  }

  Future<void> _createGuideRmsHistoryTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS guide_rms_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        mount_id TEXT NOT NULL,
        target_id INTEGER,
        total_rms_arcsec REAL NOT NULL,
        sample_count INTEGER NOT NULL,
        exposure_seconds REAL,
        recorded_at INTEGER NOT NULL
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_guide_rms_mount_recent '
      'ON guide_rms_history (mount_id, recorded_at DESC)',
    );
  }

  Future<void> _ensureCapturedImagesProducingNodeColumns() async {
    if (!await _columnExists('captured_images', 'producing_node_id')) {
      await customStatement(
        'ALTER TABLE captured_images ADD COLUMN producing_node_id TEXT',
      );
    }
    if (!await _columnExists('captured_images', 'producing_run_id')) {
      await customStatement(
        'ALTER TABLE captured_images ADD COLUMN producing_run_id TEXT',
      );
    }
    if (!await _columnExists('captured_images', 'runtime_grade')) {
      await customStatement(
        'ALTER TABLE captured_images ADD COLUMN runtime_grade TEXT',
      );
    }
    if (!await _columnExists('captured_images', 'eccentricity')) {
      await customStatement(
        'ALTER TABLE captured_images ADD COLUMN eccentricity REAL',
      );
    }
    // P1-13: thumbnail sidecar path. Declared as a raw-DDL column rather than
    // a Drift table column to match the existing producing-node convention —
    // additive nullable text columns don't need Drift codegen churn and the
    // sidecar service reads/writes it via `customStatement`. Called from
    // onCreate (fresh installs) and via the v37 onUpgrade branch.
    await _ensureCapturedImagesThumbnailPathColumn();
  }

  Future<void> _ensureCapturedImagesThumbnailPathColumn() async {
    if (!await _columnExists('captured_images', 'thumbnail_path')) {
      await customStatement(
        'ALTER TABLE captured_images ADD COLUMN thumbnail_path TEXT',
      );
    }
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

    // Wave 6 Agent 5 — notes_journal table. Managed with raw DDL (matches
    // the v27 scheduler tables + v28 defect_maps convention). Created
    // here so fresh installs (which run `onCreate` rather than
    // `onUpgrade`) also get the table; the v29 migration block above
    // covers in-place upgrades. The accompanying [NotesService] also
    // re-runs these statements through its own `_ensureSchema()` so
    // newly-installed services are tolerant of a pre-v29 connection.
    await customStatement(
      'CREATE TABLE IF NOT EXISTS notes_journal ('
      'id TEXT PRIMARY KEY NOT NULL,'
      'target_id TEXT NOT NULL,'
      'sequence_run_id INTEGER,'
      'created_at INTEGER NOT NULL,'
      'updated_at INTEGER NOT NULL,'
      'title TEXT,'
      'body TEXT NOT NULL,'
      'tags_json TEXT NOT NULL DEFAULT \'[]\','
      'attachments_json TEXT NOT NULL DEFAULT \'[]\','
      'sentiment TEXT)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_notes_journal_target '
      'ON notes_journal (target_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_notes_journal_run '
      'ON notes_journal (sequence_run_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_notes_journal_created '
      'ON notes_journal (created_at)',
    );
    // Wave 6 Thumbnails (v30) — fresh-install indexes for the producing-
    // node provenance columns added by `_ensureCapturedImagesProducingNodeColumns`.
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_images_producing_node '
      'ON captured_images (producing_node_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_images_producing_run '
      'ON captured_images (producing_run_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_images_node_captured_at '
      'ON captured_images (producing_node_id, captured_at)',
    );

    await _createGuideRmsHistoryTable();

    // Wave 8 Replay Debug (v33) — sequence_decisions table.
    // Fresh-install path; the v33 onUpgrade block handles the
    // in-place upgrade. Idempotent so re-running is safe.
    await customStatement(
      'CREATE TABLE IF NOT EXISTS sequence_decisions ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT,'
      'sequence_run_id INTEGER,'
      'timestamp_unix_ms INTEGER NOT NULL,'
      'category TEXT NOT NULL,'
      'summary TEXT NOT NULL,'
      'details_json TEXT NOT NULL DEFAULT \'{}\','
      'node_id TEXT)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sequence_decisions_run '
      'ON sequence_decisions (sequence_run_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sequence_decisions_timestamp '
      'ON sequence_decisions (timestamp_unix_ms)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sequence_decisions_category '
      'ON sequence_decisions (category)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sequence_decisions_run_ts '
      'ON sequence_decisions (sequence_run_id, timestamp_unix_ms)',
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

  Future<bool> _tableExists(String table) async {
    final result = await customSelect(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = '$table'",
    ).get();
    return result.isNotEmpty;
  }
}
