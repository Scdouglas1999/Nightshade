part of '../database.dart';

extension _NightshadeDatabaseMigrationV23ToV31 on NightshadeDatabase {
  Future<void> _upgradeSchemaV23ToV31(Migrator m, int from) async {
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
    // The DefectMaps drift Table class is declared in
    // `tables/defect_map_table.dart` and registered in @DriftDatabase
    // above, but `database.g.dart` has not yet been regenerated to
    // emit the `defectMaps` getter. Use raw DDL here so the migration
    // works ahead of the codegen pass; once `melos run generate` runs,
    // this block can be swapped back to `m.createTable(defectMaps)`.
    if (from < 28) {
      await customStatement(
        'CREATE TABLE IF NOT EXISTS defect_maps ('
        'id INTEGER PRIMARY KEY AUTOINCREMENT,'
        'camera_id TEXT NOT NULL,'
        'width INTEGER NOT NULL,'
        'height INTEGER NOT NULL,'
        'temperature_bucket_decicelsius INTEGER NOT NULL,'
        'bitmap BLOB NOT NULL,'
        'defective_pixel_count INTEGER NOT NULL,'
        'file_path TEXT,'
        'last_rebuilt_at INTEGER NOT NULL DEFAULT (CAST(strftime(\'%s\', \'now\') AS INTEGER)))',
      );
      await customStatement(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_defect_maps_lookup '
        'ON defect_maps (camera_id, width, height, temperature_bucket_decicelsius)',
      );
    }

    // Version 29: Per-target / per-run notes/journal entries (Wave 6
    // Agent 5). Managed with raw DDL — same convention as the v27
    // scheduler tables and the v28 defect_maps table — so the
    // migration lands without forcing a drift codegen pass. The
    // accompanying [NotesService] performs all reads/writes via
    // `customSelect`/`customStatement`.
    //
    // Schema design:
    //   * `id` is a UUID string (TEXT PRIMARY KEY) for future
    //     cross-machine sync; never reused on updates.
    //   * `target_id` is a logical TEXT identifier (catalog id like
    //     "M31", or display name) rather than an FK to `targets.id`
    //     so that renaming or recreating a target row does not
    //     silently NULL-out its notes.
    //   * `sequence_run_id` is a soft INT pointer to the
    //     `sequence_runs` row when the note is run-scoped; no FK so
    //     deleting an old run record does not cascade-delete the
    //     journal entry.
    //   * `tags_json` / `attachments_json` store JSON arrays of
    //     strings — search-by-tag uses plain LIKE which is enough
    //     for the small per-user dataset (typically <10k notes).
    //   * `sentiment` is the literal emoji string from the
    //     auto-prompt sentiment dropdown, or NULL when not set.
    if (from < 29) {
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
    }

    // Version 30: Inline frame thumbnails (Wave 6 Agent 4 — Thumbnails).
    //
    // Add provenance + grading columns to `captured_images` so each
    // captured frame can be tied back to the ExposureNode that
    // produced it and the sequence_runs row that was active at the
    // time. This is what powers the inline thumbnail strip under
    // each ExposureNode in the sequence tree.
    //
    // All three columns are nullable: legacy rows + ad-hoc captures
    // outside a sequence simply leave them unset. We index
    // producing_node_id (alone and paired with captured_at) because
    // the new `watchImagesByProducingNode` DAO method is the hottest
    // path — it queries by node id and orders by captured_at.
    if (from < 30) {
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

      // I4 fix: guide_rms_history.exposure_seconds must be nullable
      // post-v30. SQLite has no ALTER COLUMN, so we rename-create-copy-drop
      // and recreate the helper index. We do this conditionally — only when
      // the column currently has a NOT NULL constraint, so a fresh v30+
      // install (created via the v30 raw DDL above) doesn't pay the rebuild
      // cost on every startup.
      // Guard: only touch guide_rms_history if it already exists in this
      // DB. The table is first created at the v34 step below
      // (_createGuideRmsHistoryTable), so a database upgrading from < 30
      // does NOT have it yet here — the unconditional CREATE INDEX below
      // otherwise threw "no such table: guide_rms_history" and aborted the
      // entire migration (app failed to open). Older DBs correctly skip
      // this block and get the nullable table + index from v34.
      if (await _tableExists('guide_rms_history')) {
        final exposureNotNullInfo = await customSelect(
          "SELECT \"notnull\" FROM pragma_table_info('guide_rms_history') "
          "WHERE name = 'exposure_seconds'",
        ).get();
        if (exposureNotNullInfo.isNotEmpty &&
            exposureNotNullInfo.first.data['notnull'] == 1) {
          await customStatement(
            'ALTER TABLE guide_rms_history RENAME TO guide_rms_history_v29',
          );
          await customStatement(
            'CREATE TABLE guide_rms_history ('
            'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
            'session_id TEXT NOT NULL, '
            'mount_id TEXT NOT NULL, '
            'target_id INTEGER NULL, '
            'total_rms_arcsec REAL NOT NULL, '
            'sample_count INTEGER NOT NULL, '
            'exposure_seconds REAL, '
            'recorded_at INTEGER NOT NULL'
            ')',
          );
          await customStatement(
            'INSERT INTO guide_rms_history '
            '(id, session_id, mount_id, target_id, total_rms_arcsec, '
            'sample_count, exposure_seconds, recorded_at) '
            'SELECT id, session_id, mount_id, target_id, total_rms_arcsec, '
            'sample_count, exposure_seconds, recorded_at '
            'FROM guide_rms_history_v29',
          );
          await customStatement('DROP TABLE guide_rms_history_v29');
        }
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_guide_rms_mount_recent '
          'ON guide_rms_history (mount_id, recorded_at DESC)',
        );
      }
    }

    // Version 31: Persisted predictive autofocus models (per-filter).
    //
    // Adds the `focus_models` table that stores the learned linear
    // regression between focuser temperature and best-focus position,
    // keyed by (equipment_profile_id, filter_name). Powers the Wave 8
    // predictive autofocus feature — confidence-gated prediction,
    // cross-session persistence, and drift-detection notifications.
    //
    // Backwards compat: the legacy JSON-file
    // [FocusModelService] continues to work unchanged. The DB rows
    // here are written by [PredictiveAfService] and are additive.
    if (from < 31) {
      await _createFocusModelsTable();
      await customStatement(
        "INSERT OR IGNORE INTO app_settings (key, value) VALUES ('predictive_af.enabled', 'true')",
      );
      await customStatement(
        "INSERT OR IGNORE INTO app_settings (key, value) VALUES ('predictive_af.min_samples_for_trust', '8')",
      );
      await customStatement(
        "INSERT OR IGNORE INTO app_settings (key, value) VALUES ('predictive_af.high_confidence_threshold', '0.8')",
      );
      await customStatement(
        "INSERT OR IGNORE INTO app_settings (key, value) VALUES ('predictive_af.low_confidence_threshold', '0.5')",
      );
      await customStatement(
        "INSERT OR IGNORE INTO app_settings (key, value) VALUES ('predictive_af.drift_threshold_steps', '200')",
      );
      await customStatement(
        "INSERT OR IGNORE INTO app_settings (key, value) VALUES ('predictive_af.drift_runs_before_warn', '5')",
      );
    }
  }
}
