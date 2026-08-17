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

  /// Thumbnail (v30) — add producing-node provenance columns to
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

  /// Create the v41 post-session integration tables — `integrated_masters`,
  /// `integrated_master_frames`, and `flat_library` — plus their indexes.
  ///
  /// Called from both `onCreate` (fresh installs) and the `if (from < 41)`
  /// `onUpgrade` branch. Every statement is `CREATE ... IF NOT EXISTS` so the
  /// helper is idempotent and re-runnable. These are raw-DDL tables (the
  /// dominant v27+ convention) accessed via `IntegratedMastersDao` /
  /// `FlatLibraryDao`; see `tables/post_session_tables.dart` for the canonical
  /// schema documentation. `ON DELETE` foreign keys mirror `stacked_results` /
  /// `projects`; FK enforcement is already enabled in `beforeOpen`.
  Future<void> _createPostSessionTables() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS integrated_masters('
      'id INTEGER PRIMARY KEY AUTOINCREMENT,'
      'target_id INTEGER REFERENCES targets(id) ON DELETE SET NULL,'
      'name TEXT NOT NULL,'
      'master_fits_path TEXT,'
      'preview_png_path TEXT,'
      'sidecar_path TEXT,'
      'rejection_map_path TEXT,'
      "status TEXT NOT NULL DEFAULT 'finalized',"
      "accumulation_mode TEXT NOT NULL DEFAULT 'batch',"
      'channels INTEGER NOT NULL DEFAULT 1,'
      'width INTEGER NOT NULL DEFAULT 0,'
      'height INTEGER NOT NULL DEFAULT 0,'
      'frame_count INTEGER NOT NULL DEFAULT 0,'
      'total_integration_seconds REAL NOT NULL DEFAULT 0.0,'
      'filter TEXT,'
      "settings_json TEXT NOT NULL DEFAULT '{}',"
      "stats_json TEXT NOT NULL DEFAULT '{}',"
      'created_at INTEGER NOT NULL,'
      'updated_at INTEGER NOT NULL)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_integrated_masters_target '
      'ON integrated_masters (target_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_integrated_masters_status '
      'ON integrated_masters (status)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_integrated_masters_created '
      'ON integrated_masters (created_at)',
    );

    await customStatement(
      'CREATE TABLE IF NOT EXISTS integrated_master_frames('
      'id INTEGER PRIMARY KEY AUTOINCREMENT,'
      'master_id INTEGER NOT NULL '
      'REFERENCES integrated_masters(id) ON DELETE CASCADE,'
      'image_id INTEGER NOT NULL '
      'REFERENCES captured_images(id) ON DELETE CASCADE,'
      'weight REAL,'
      'alignment_residual_px REAL,'
      'accepted INTEGER NOT NULL DEFAULT 1,'
      'rejection_reason TEXT,'
      'folded_at INTEGER NOT NULL,'
      'UNIQUE(master_id, image_id))',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_integrated_master_frames_master '
      'ON integrated_master_frames (master_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_integrated_master_frames_image '
      'ON integrated_master_frames (image_id)',
    );

    await customStatement(
      'CREATE TABLE IF NOT EXISTS flat_library('
      'id INTEGER PRIMARY KEY AUTOINCREMENT,'
      'file_path TEXT NOT NULL,'
      'filter TEXT,'
      'equipment_profile_id INTEGER '
      'REFERENCES equipment_profiles(id) ON DELETE SET NULL,'
      'optical_train_id TEXT,'
      'temperature REAL,'
      'gain INTEGER NOT NULL DEFAULT 0,'
      'offset INTEGER NOT NULL DEFAULT 0,'
      'bin_x INTEGER NOT NULL DEFAULT 1,'
      'bin_y INTEGER NOT NULL DEFAULT 1,'
      'width INTEGER,'
      'height INTEGER,'
      "flat_kind TEXT NOT NULL DEFAULT 'sky',"
      'master_frame_count INTEGER NOT NULL DEFAULT 0,'
      'created_at INTEGER NOT NULL)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_flat_library_filter '
      'ON flat_library (filter)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_flat_library_profile '
      'ON flat_library (equipment_profile_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_flat_library_match '
      'ON flat_library (filter, gain, bin_x, bin_y)',
    );
  }

  /// Add durable display-preview paths for post-session diagnostic maps.
  ///
  /// The original v41 schema retained only the scientific rejection-map FITS,
  /// and retained no drizzle coverage artifact at all. The UI nevertheless
  /// handed that FITS path to `Image.file`, so its Rejection toggle could never
  /// decode; Coverage was permanently absent. These nullable v57 columns keep
  /// both scientific coverage FITS and the two real PNG overlays.
  Future<void> _ensureIntegratedMastersOverlayColumns() async {
    if (!await _columnExists(
      'integrated_masters',
      'rejection_map_preview_path',
    )) {
      await customStatement(
        'ALTER TABLE integrated_masters '
        'ADD COLUMN rejection_map_preview_path TEXT',
      );
    }
    if (!await _columnExists('integrated_masters', 'coverage_map_path')) {
      await customStatement(
        'ALTER TABLE integrated_masters ADD COLUMN coverage_map_path TEXT',
      );
    }
    if (!await _columnExists(
      'integrated_masters',
      'coverage_map_preview_path',
    )) {
      await customStatement(
        'ALTER TABLE integrated_masters '
        'ADD COLUMN coverage_map_preview_path TEXT',
      );
    }
  }

  /// Create the v42 `night_reports` table — one Night Doctor report per session
  /// (and/or target) produced by the Smart Morning Report pipeline — plus its
  /// lookup indexes.
  ///
  /// Called from both `onCreate` (fresh installs) and the `if (from < 42)`
  /// `onUpgrade` branch. Every statement is `CREATE ... IF NOT EXISTS` so the
  /// helper is idempotent and re-runnable. This is a raw-DDL table (the dominant
  /// v27+ convention) accessed via `NightReportsDao`; see
  /// `tables/post_session_tables.dart` for the canonical schema documentation.
  /// FK columns mirror `stacked_results`: `session_id` and `target_id` are both
  /// nullable so a report can attach to a session, a target, or both. FK
  /// enforcement is already enabled in `beforeOpen`.
  Future<void> _createNightReportsTable() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS night_reports('
      'id INTEGER PRIMARY KEY AUTOINCREMENT,'
      'session_id INTEGER REFERENCES imaging_sessions(id) ON DELETE CASCADE,'
      'target_id INTEGER REFERENCES targets(id) ON DELETE SET NULL,'
      'score INTEGER NOT NULL DEFAULT 0,'
      "headline TEXT NOT NULL DEFAULT '',"
      "findings_json TEXT NOT NULL DEFAULT '[]',"
      'created_at INTEGER NOT NULL)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_night_reports_session '
      'ON night_reports (session_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_night_reports_target '
      'ON night_reports (target_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_night_reports_created '
      'ON night_reports (created_at)',
    );
  }

  /// Add the v42 additive Smart-Morning-Report columns to the raw-DDL
  /// `integrated_masters` and `integrated_master_frames` tables.
  ///
  /// Because both tables are raw-DDL (not Drift `Table` classes), additive
  /// nullable columns are retrofitted with guarded `ALTER TABLE ... ADD COLUMN`
  /// — the exact pattern of `_ensureCapturedImagesProducingNodeColumns`. Every
  /// ALTER is guarded by `_columnExists` so the helper is idempotent and runs
  /// safely from both `onCreate` (fresh installs — the columns are NOT in
  /// `_createPostSessionTables`, so a fresh install needs this too) and the
  /// `if (from < 42)` `onUpgrade` branch.
  Future<void> _ensureIntegratedMastersV42Columns() async {
    // integrated_masters: finishing artifacts + target SNR/time goals + the
    // marginal-SNR improvement curve.
    if (!await _columnExists('integrated_masters', 'color_calibrated_path')) {
      await customStatement(
        'ALTER TABLE integrated_masters ADD COLUMN color_calibrated_path TEXT',
      );
    }
    if (!await _columnExists('integrated_masters', 'annotated_preview_path')) {
      await customStatement(
        'ALTER TABLE integrated_masters ADD COLUMN annotated_preview_path TEXT',
      );
    }
    if (!await _columnExists('integrated_masters', 'background_extracted')) {
      await customStatement(
        'ALTER TABLE integrated_masters '
        'ADD COLUMN background_extracted INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!await _columnExists('integrated_masters', 'target_snr')) {
      await customStatement(
        'ALTER TABLE integrated_masters ADD COLUMN target_snr REAL',
      );
    }
    if (!await _columnExists('integrated_masters', 'target_integration_s')) {
      await customStatement(
        'ALTER TABLE integrated_masters ADD COLUMN target_integration_s REAL',
      );
    }
    if (!await _columnExists('integrated_masters', 'improvement_curve_json')) {
      await customStatement(
        'ALTER TABLE integrated_masters ADD COLUMN improvement_curve_json TEXT',
      );
    }

    // integrated_master_frames: per-sub science data the Night Doctor reads
    // after a morning integration (snr / fwhm / eccentricity).
    if (!await _columnExists('integrated_master_frames', 'snr')) {
      await customStatement(
        'ALTER TABLE integrated_master_frames ADD COLUMN snr REAL',
      );
    }
    if (!await _columnExists('integrated_master_frames', 'fwhm')) {
      await customStatement(
        'ALTER TABLE integrated_master_frames ADD COLUMN fwhm REAL',
      );
    }
    if (!await _columnExists('integrated_master_frames', 'eccentricity')) {
      await customStatement(
        'ALTER TABLE integrated_master_frames ADD COLUMN eccentricity REAL',
      );
    }
  }

  /// Create the v43 `campaigns` table — the durable NINA-style multi-night
  /// `(target, filter, accepted, desired, last_date)` counter — plus its
  /// lookup index.
  ///
  /// Called from both `onCreate` (fresh installs) and the `if (from < 43)`
  /// `onUpgrade` branch. Every statement is `CREATE ... IF NOT EXISTS` so the
  /// helper is idempotent and re-runnable. This is a raw-DDL table (the dominant
  /// v27+ convention) accessed via `CampaignsDao`. The `ON DELETE CASCADE`
  /// foreign key mirrors `integration_goals`; FK enforcement is already enabled
  /// in `beforeOpen` (`PRAGMA foreign_keys = ON`), so deleting a target tears
  /// down its campaign rows automatically.
  ///
  /// `UNIQUE(target_id, filter)` makes the `(target, filter)` pair the campaign
  /// identity. The table is ADDITIVE and orthogonal to `integration_goals`: it
  /// never feeds the live `SchedulerEngine` goals-complete reject (which stays a
  /// read-only derivation), it is a denormalized bookkeeping counter the
  /// campaign UI can later show.
  Future<void> _createCampaignsTable() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS campaigns('
      'id INTEGER PRIMARY KEY AUTOINCREMENT,'
      'target_id INTEGER NOT NULL REFERENCES targets(id) ON DELETE CASCADE,'
      'filter TEXT NOT NULL,'
      'accepted_count INTEGER NOT NULL DEFAULT 0,'
      'desired_count INTEGER NOT NULL DEFAULT 0,'
      'last_date INTEGER,'
      'created_at INTEGER NOT NULL,'
      'updated_at INTEGER NOT NULL,'
      'UNIQUE(target_id, filter))',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_campaigns_target '
      'ON campaigns (target_id)',
    );
  }

  /// Add the v44 additive Phase C "finishing foundation" columns to the
  /// raw-DDL `integrated_masters` table — the per-master plate-solved WCS (eight
  /// CD-matrix scalars) plus the finishing-artifact output paths.
  ///
  /// Because `integrated_masters` is a raw-DDL table (not a Drift `Table`
  /// class), additive nullable columns are retrofitted with guarded
  /// `ALTER TABLE ... ADD COLUMN` — the exact pattern of
  /// `_ensureIntegratedMastersV42Columns`. Every ALTER is guarded by
  /// `_columnExists` so the helper is idempotent and runs safely from both
  /// `onCreate` (fresh installs — the columns are NOT in
  /// `_createPostSessionTables`, so a fresh install needs this too) and the
  /// `if (from < 44)` `onUpgrade` branch.
  ///
  /// The WCS columns store the eight scalars in the CD-matrix form ASTAP emits
  /// (see `WcsInfo::from_plate_solve`, `imaging/src/fits.rs:1094`): reference
  /// world coordinates, reference pixel, and the 2x2 CD matrix. The finishing
  /// paths persist the gated post-step outputs (`<master>_bgx/_decon/_starred`).
  Future<void> _ensureIntegratedMastersV44Columns() async {
    // Plate-solved WCS — reference world coordinates (CRVAL1/2, degrees).
    if (!await _columnExists('integrated_masters', 'wcs_crval1')) {
      await customStatement(
        'ALTER TABLE integrated_masters ADD COLUMN wcs_crval1 REAL',
      );
    }
    if (!await _columnExists('integrated_masters', 'wcs_crval2')) {
      await customStatement(
        'ALTER TABLE integrated_masters ADD COLUMN wcs_crval2 REAL',
      );
    }
    // Reference pixel (CRPIX1/2 — usually the image centre).
    if (!await _columnExists('integrated_masters', 'wcs_crpix1')) {
      await customStatement(
        'ALTER TABLE integrated_masters ADD COLUMN wcs_crpix1 REAL',
      );
    }
    if (!await _columnExists('integrated_masters', 'wcs_crpix2')) {
      await customStatement(
        'ALTER TABLE integrated_masters ADD COLUMN wcs_crpix2 REAL',
      );
    }
    // CD matrix (scale + rotation), four scalars.
    if (!await _columnExists('integrated_masters', 'wcs_cd1_1')) {
      await customStatement(
        'ALTER TABLE integrated_masters ADD COLUMN wcs_cd1_1 REAL',
      );
    }
    if (!await _columnExists('integrated_masters', 'wcs_cd1_2')) {
      await customStatement(
        'ALTER TABLE integrated_masters ADD COLUMN wcs_cd1_2 REAL',
      );
    }
    if (!await _columnExists('integrated_masters', 'wcs_cd2_1')) {
      await customStatement(
        'ALTER TABLE integrated_masters ADD COLUMN wcs_cd2_1 REAL',
      );
    }
    if (!await _columnExists('integrated_masters', 'wcs_cd2_2')) {
      await customStatement(
        'ALTER TABLE integrated_masters ADD COLUMN wcs_cd2_2 REAL',
      );
    }

    // Finishing-artifact output paths.
    if (!await _columnExists(
      'integrated_masters',
      'background_extracted_path',
    )) {
      await customStatement(
        'ALTER TABLE integrated_masters '
        'ADD COLUMN background_extracted_path TEXT',
      );
    }
    if (!await _columnExists('integrated_masters', 'deconvolved_path')) {
      await customStatement(
        'ALTER TABLE integrated_masters ADD COLUMN deconvolved_path TEXT',
      );
    }
    if (!await _columnExists('integrated_masters', 'star_reduced_path')) {
      await customStatement(
        'ALTER TABLE integrated_masters ADD COLUMN star_reduced_path TEXT',
      );
    }
  }

  /// Create the v44 `narrowband_composites` table — one row per applied
  /// SHO/HOO/etc. palette combine — plus its lookup index.
  ///
  /// Called from both `onCreate` (fresh installs) and the `if (from < 44)`
  /// `onUpgrade` branch. The single statement is `CREATE TABLE IF NOT EXISTS`,
  /// so the helper is idempotent and re-runnable. This is a raw-DDL table (the
  /// dominant v27+ convention) accessed via [NarrowbandCompositesDao]. The
  /// `ON DELETE SET NULL` foreign key mirrors `integrated_masters.target_id`;
  /// FK enforcement is already enabled in `beforeOpen`
  /// (`PRAGMA foreign_keys = ON`).
  ///
  /// `component_master_ids` is a JSON array of the `integrated_masters.id`
  /// component channels the composite was built from (e.g. the Ha/OIII/SII
  /// masters), and `palette` is the palette name (`SHO`, `HOO`, ...).
  Future<void> _createNarrowbandCompositesTable() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS narrowband_composites('
      'id INTEGER PRIMARY KEY AUTOINCREMENT,'
      'target_id INTEGER REFERENCES targets(id) ON DELETE SET NULL,'
      "palette TEXT NOT NULL DEFAULT '',"
      "component_master_ids TEXT NOT NULL DEFAULT '[]',"
      'output_path TEXT NOT NULL,'
      'width INTEGER NOT NULL DEFAULT 0,'
      'height INTEGER NOT NULL DEFAULT 0,'
      'created_at INTEGER NOT NULL)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_narrowband_composites_target '
      'ON narrowband_composites (target_id)',
    );
  }

  /// Create the v45 `mosaic_projects` + `mosaic_panels` tables (Mosaic M2),
  /// making a mosaic a first-class durable entity linking grid config → panel
  /// targets → panel masters → the stitched output.
  ///
  /// Called from both `onCreate` (fresh installs) and the `if (from < 45)`
  /// `onUpgrade` branch. Every statement is `CREATE TABLE/INDEX IF NOT EXISTS`,
  /// so the helper is idempotent and re-runnable. These are raw-DDL tables (the
  /// dominant v27+ convention) accessed via [MosaicProjectsDao] /
  /// [MosaicPanelsDao], mirroring [CampaignsDao] / [NarrowbandCompositesDao].
  ///
  /// `mosaic_projects.target_id` and `output_master_id` use `ON DELETE SET NULL`
  /// (a project survives its source target / stitched master being removed);
  /// `mosaic_panels.project_id` uses `ON DELETE CASCADE` (panels are owned by
  /// their project), while the per-panel `target_id` / `integrated_master_id`
  /// use `ON DELETE SET NULL`. FK enforcement is already on in `beforeOpen`
  /// (`PRAGMA foreign_keys = ON`).
  ///
  /// Each panel's plate-solved WCS rides on its `integrated_masters` row (v44
  /// WCS columns) via `integrated_master_id` — there are no duplicate WCS
  /// columns on `mosaic_panels`. The stitched output is itself an
  /// `integrated_masters` row referenced by `mosaic_projects.output_master_id`,
  /// so it flows into the existing master library + morning report unchanged.
  /// `UNIQUE(project_id, panel_index)` makes `(project, panel)` the panel
  /// identity (panel_index is 0-based, matching the FITS `NS-PIDX` provenance).
  Future<void> _createMosaicTables() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS mosaic_projects('
      'id INTEGER PRIMARY KEY AUTOINCREMENT,'
      'target_id INTEGER REFERENCES targets(id) ON DELETE SET NULL,'
      'name TEXT NOT NULL,'
      'rows INTEGER NOT NULL,'
      'cols INTEGER NOT NULL,'
      'overlap_pct REAL NOT NULL DEFAULT 15.0,'
      'position_angle_deg REAL NOT NULL DEFAULT 0.0,'
      "status TEXT NOT NULL DEFAULT 'planning',"
      'output_master_id INTEGER '
      'REFERENCES integrated_masters(id) ON DELETE SET NULL,'
      'created_at INTEGER NOT NULL,'
      'updated_at INTEGER NOT NULL,'
      // v56: when an owner publishes this project to the
      // hub as a collaborative mosaic, `hub_mosaic_id` is the hub mosaic id (the
      // handle claim/upload/assemble act on), `collab_role` is owner|participant,
      // and `collab_status` mirrors the hub lifecycle (published|assembling|
      // complete). All nullable — a local-only project never publishes.
      // Retrofitted onto pre-v56 DBs by the v56 onUpgrade branch.
      'hub_mosaic_id TEXT,'
      'collab_role TEXT,'
      'collab_status TEXT)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_mosaic_projects_target '
      'ON mosaic_projects (target_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_mosaic_projects_status '
      'ON mosaic_projects (status)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_mosaic_projects_hub '
      'ON mosaic_projects (hub_mosaic_id)',
    );

    await customStatement(
      'CREATE TABLE IF NOT EXISTS mosaic_panels('
      'id INTEGER PRIMARY KEY AUTOINCREMENT,'
      'project_id INTEGER NOT NULL '
      'REFERENCES mosaic_projects(id) ON DELETE CASCADE,'
      'panel_index INTEGER NOT NULL,'
      'center_ra REAL NOT NULL,'
      'center_dec REAL NOT NULL,'
      'target_id INTEGER REFERENCES targets(id) ON DELETE SET NULL,'
      'integrated_master_id INTEGER '
      'REFERENCES integrated_masters(id) ON DELETE SET NULL,'
      'captured_count INTEGER NOT NULL DEFAULT 0,'
      "status TEXT NOT NULL DEFAULT 'pending',"
      // v56: distributed-capture panel claim. When a
      // mosaic is published to the hub, a panel is claimed by a rig/user (the
      // hand-off baton pattern), and its uploaded panel master is tracked here.
      // `assigned_rig_id` / `assigned_user_id` carry the hub identities,
      // `claim_token` the hub-issued claim baton, and `uploaded_master_id` the
      // local `integrated_masters.id` of the panel master uploaded. All
      // nullable — a panel is unclaimed until a rig takes it. Retrofitted onto
      // pre-v56 DBs by the v56 onUpgrade branch.
      'assigned_rig_id TEXT,'
      'assigned_user_id TEXT,'
      'claim_token TEXT,'
      'uploaded_master_id INTEGER,'
      'UNIQUE(project_id, panel_index))',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_mosaic_panels_project '
      'ON mosaic_panels (project_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_mosaic_panels_master '
      'ON mosaic_panels (integrated_master_id)',
    );
  }

  /// v46 (Calibration Library Manager): user tags / notes plus the
  /// FITS-enriched camera-id cache, keyed by `(master_type, master_id)`
  /// where `master_id` is the row id in the artifact's source table
  /// (`dark_library` / `flat_library` / `defect_maps`). Raw DDL + plain
  /// [CalibrationTagsDao], mirroring [FlatLibraryDao].
  Future<void> _createCalibrationTagsTable() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS calibration_tags('
      'id INTEGER PRIMARY KEY AUTOINCREMENT,'
      'master_type TEXT NOT NULL,'
      'master_id INTEGER NOT NULL,'
      "tags_json TEXT NOT NULL DEFAULT '[]',"
      'notes TEXT,'
      'camera_id TEXT,'
      // v56: sharing / provenance. `shared_by` is the
      // sharer's hub account id, `shared_at` an epoch-seconds timestamp,
      // `license` a `ContributionLicense` wire name, and `provenance_json` a
      // serialized [Provenance]. `published_remote_id` is the hub master id this
      // LOCAL master was published under (the owner-scoped retract handle);
      // null until the master is shared, cleared again on retract. All nullable —
      // a master is local-only until shared. Retrofitted onto pre-v56 DBs by the
      // v56 onUpgrade branch.
      'shared_by TEXT,'
      'shared_at INTEGER,'
      'license TEXT,'
      'provenance_json TEXT,'
      'published_remote_id TEXT,'
      'updated_at INTEGER NOT NULL,'
      'UNIQUE(master_type, master_id))',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_calibration_tags_camera '
      'ON calibration_tags (camera_id)',
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
    if (!await _columnExists('captured_images', 'fwhm')) {
      await customStatement('ALTER TABLE captured_images ADD COLUMN fwhm REAL');
    }
    // v51: anisotropic WCS — the four CD-matrix scalars plus a `solved_sip`
    // JSON blob. Raw-DDL columns retrofitted by the v51 onUpgrade branch;
    // fresh installs add them here.
    if (!await _columnExists('captured_images', 'solved_cd1_1')) {
      await customStatement(
        'ALTER TABLE captured_images ADD COLUMN solved_cd1_1 REAL',
      );
    }
    if (!await _columnExists('captured_images', 'solved_cd1_2')) {
      await customStatement(
        'ALTER TABLE captured_images ADD COLUMN solved_cd1_2 REAL',
      );
    }
    if (!await _columnExists('captured_images', 'solved_cd2_1')) {
      await customStatement(
        'ALTER TABLE captured_images ADD COLUMN solved_cd2_1 REAL',
      );
    }
    if (!await _columnExists('captured_images', 'solved_cd2_2')) {
      await customStatement(
        'ALTER TABLE captured_images ADD COLUMN solved_cd2_2 REAL',
      );
    }
    if (!await _columnExists('captured_images', 'solved_sip')) {
      await customStatement(
        'ALTER TABLE captured_images ADD COLUMN solved_sip TEXT',
      );
    }
    // Thumbnail sidecar path. Declared as a raw-DDL column rather than
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

    // Notes_journal table. Managed with raw DDL (matches
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
    // Thumbnail (v30) — fresh-install indexes for the producing-
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

    // Replay Debug (v33) — sequence_decisions table.
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

    // Living Sky — Wave 3 (v55) scale indexes. Created here so fresh installs
    // (onCreate path) get them; the v55 onUpgrade block covers in-place
    // upgrades. Idempotent (IF NOT EXISTS), so re-running is safe.
    await _createLivingSkyWave3Indexes();
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

  /// Drop `app_settings` rows whose key no longer has an owner. Runs on every
  /// open so a profile created by an older build stops serving (and exporting)
  /// a value nothing maintains. See [_retiredSettingKeys].
  Future<void> _pruneRetiredSettings() async {
    for (final key in _retiredSettingKeys) {
      await customStatement('DELETE FROM app_settings WHERE key = ?', [key]);
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

  /// Create the v58 Darkroom tables — `recipes`, `darkroom_jobs`,
  /// `delivery_targets`, and `delivery_journal` — plus their indexes.
  ///
  /// Called from both `onCreate` (fresh installs) and the `if (from < 58)`
  /// `onUpgrade` branch. Every statement is `CREATE ... IF NOT EXISTS` so the
  /// helper is idempotent and re-runnable. These are raw-DDL tables (the
  /// dominant v27+ convention) accessed via `RecipesDao` / `DarkroomJobsDao` /
  /// `DeliveryTargetsDao` / `DeliveryJournalDao`; see
  /// `tables/darkroom_tables.dart` for the canonical schema documentation.
  ///
  /// Ordering matters on the fresh-install path: `delivery_journal` references
  /// both `delivery_targets` and `darkroom_jobs`, and `recipes` references
  /// `integrated_masters`, so this runs after `_createPostSessionTables`.
  ///
  /// Every enum-valued column carries a `CHECK` listing its legal wire strings.
  /// The DAOs validate before writing, so a `CHECK` firing means a caller
  /// bypassed them; it is the backstop, not the first line.
  Future<void> _createDarkroomTables() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS recipes('
      'id INTEGER PRIMARY KEY AUTOINCREMENT,'
      'target_id INTEGER REFERENCES targets(id) ON DELETE SET NULL,'
      'session_id INTEGER REFERENCES imaging_sessions(id) ON DELETE SET NULL,'
      'master_id INTEGER '
      'REFERENCES integrated_masters(id) ON DELETE SET NULL,'
      'base_master_path TEXT NOT NULL,'
      "name TEXT NOT NULL DEFAULT '',"
      "steps_json TEXT NOT NULL DEFAULT '[]',"
      "created_by TEXT NOT NULL DEFAULT 'autopilot',"
      'parent_recipe_id INTEGER REFERENCES recipes(id) ON DELETE RESTRICT,'
      'divergence_index INTEGER,'
      'schema_version INTEGER NOT NULL DEFAULT 1,'
      'created_at INTEGER NOT NULL,'
      'updated_at INTEGER NOT NULL,'
      "CHECK (created_by IN ('autopilot', 'user')),"
      'CHECK (schema_version >= 1),'
      'CHECK (divergence_index IS NULL OR divergence_index >= 0),'
      'CHECK ((parent_recipe_id IS NULL) = (divergence_index IS NULL)))',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_recipes_target ON recipes (target_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_recipes_session ON recipes (session_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_recipes_master ON recipes (master_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_recipes_parent '
      'ON recipes (parent_recipe_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_recipes_base_master '
      'ON recipes (base_master_path)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_recipes_created ON recipes (created_at)',
    );

    await customStatement(
      'CREATE TABLE IF NOT EXISTS darkroom_jobs('
      'id INTEGER PRIMARY KEY AUTOINCREMENT,'
      'session_id INTEGER REFERENCES imaging_sessions(id) ON DELETE CASCADE,'
      "kind TEXT NOT NULL DEFAULT 'dawn',"
      "state TEXT NOT NULL DEFAULT 'queued',"
      'progress REAL NOT NULL DEFAULT 0.0,'
      'note TEXT,'
      'error_text TEXT,'
      'attempts INTEGER NOT NULL DEFAULT 0,'
      'created_at INTEGER NOT NULL,'
      'started_at INTEGER,'
      'finished_at INTEGER,'
      "CHECK (kind IN ('dawn', 'manual')),"
      "CHECK (state IN ('queued', 'running', 'cancelled', 'done', 'failed')),"
      'CHECK (progress >= 0.0 AND progress <= 1.0),'
      'CHECK (attempts >= 0))',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_darkroom_jobs_state '
      'ON darkroom_jobs (state, created_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_darkroom_jobs_session '
      'ON darkroom_jobs (session_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_darkroom_jobs_created '
      'ON darkroom_jobs (created_at)',
    );

    await customStatement(
      'CREATE TABLE IF NOT EXISTS delivery_targets('
      'id INTEGER PRIMARY KEY AUTOINCREMENT,'
      'name TEXT NOT NULL,'
      'kind TEXT NOT NULL,'
      "config_json TEXT NOT NULL DEFAULT '{}',"
      'enabled INTEGER NOT NULL DEFAULT 1,'
      "content_json TEXT NOT NULL DEFAULT '[]',"
      'secret_ref TEXT,'
      'created_at INTEGER NOT NULL,'
      'updated_at INTEGER NOT NULL,'
      "CHECK (kind IN ('watched_folder', 'sftp', 'peer')),"
      'CHECK (enabled IN (0, 1)))',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_delivery_targets_enabled '
      'ON delivery_targets (enabled, kind)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_delivery_targets_name '
      'ON delivery_targets (name)',
    );

    await customStatement(
      'CREATE TABLE IF NOT EXISTS delivery_journal('
      'id INTEGER PRIMARY KEY AUTOINCREMENT,'
      'target_id INTEGER NOT NULL '
      'REFERENCES delivery_targets(id) ON DELETE CASCADE,'
      'job_id INTEGER NOT NULL '
      'REFERENCES darkroom_jobs(id) ON DELETE CASCADE,'
      'file_path TEXT NOT NULL,'
      'bytes INTEGER NOT NULL DEFAULT 0,'
      'checksum TEXT,'
      "state TEXT NOT NULL DEFAULT 'retrying',"
      'attempts INTEGER NOT NULL DEFAULT 0,'
      'last_error TEXT,'
      'created_at INTEGER NOT NULL,'
      'updated_at INTEGER NOT NULL,'
      'delivered_at INTEGER,'
      "CHECK (state IN ('delivered', 'failed', 'retrying')),"
      'CHECK (attempts >= 0),'
      'CHECK (bytes >= 0),'
      'UNIQUE(target_id, job_id, file_path))',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_delivery_journal_target '
      'ON delivery_journal (target_id, state)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_delivery_journal_job '
      'ON delivery_journal (job_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_delivery_journal_state '
      'ON delivery_journal (state, updated_at)',
    );
  }

  /// Close out Darkroom jobs a previous process left mid-flight.
  ///
  /// A `darkroom_jobs` row is only 'running' while THIS process's executor is
  /// driving it — that executor state lives in memory, so nothing can still be
  /// running at the moment the database opens. Any row still marked 'running'
  /// here is residue from a process that died mid-job: a crash, a force quit,
  /// or safing that ran out its shutdown budget. Left alone, such a row is
  /// permanent: the queue reports work in flight that nothing is driving, and
  /// the night's masters are never produced.
  ///
  /// Recovered rows go back to 'queued' with `started_at` cleared and a note
  /// saying what happened. `progress` is left where the dead process left it,
  /// so the report can state how far that attempt got, and `attempts` is left
  /// alone — it counts starts, and the restart will increment it.
  ///
  /// A job that has already used its [kDarkroomJobMaxAttempts] starts is moved
  /// to 'failed' instead: a job that kills the process must not re-queue itself
  /// forever. Its `note` is replaced along with its state, because the note the
  /// dead attempt left — the step it was on, or the re-queue line a previous
  /// recovery wrote — describes work that is over and would read on a failed
  /// row as though it were still going.
  Future<void> _recoverInterruptedDarkroomJobs() async {
    final failed = await customUpdate(
      "UPDATE darkroom_jobs SET state = 'failed', finished_at = ?, "
      'error_text = ?, note = ? WHERE state = ? AND attempts >= ?',
      variables: [
        Variable<int>(DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000),
        const Variable<String>(
          'Interrupted by a process exit on attempt '
          '$kDarkroomJobMaxAttempts of $kDarkroomJobMaxAttempts; not retried.',
        ),
        const Variable<String>(
          'Stopped at the retry limit; this job is not re-queued.',
        ),
        const Variable<String>('running'),
        const Variable<int>(kDarkroomJobMaxAttempts),
      ],
      updateKind: UpdateKind.update,
    );
    final requeued = await customUpdate(
      "UPDATE darkroom_jobs SET state = 'queued', started_at = NULL, "
      'note = ? WHERE state = ?',
      variables: [
        const Variable<String>(
          'Re-queued: the previous process exited while this job was running.',
        ),
        const Variable<String>('running'),
      ],
      updateKind: UpdateKind.update,
    );
    if (failed > 0 || requeued > 0) {
      // ignore: avoid_print
      print(
        '[nightshade_db] Darkroom jobs left running by a previous process: '
        're-queued $requeued, failed $failed at the attempt limit.',
      );
    }
  }

  /// The directory holding this connection's database file, or null when the
  /// database has no file (an in-memory test connection).
  ///
  /// Asked of SQLite rather than re-derived from
  /// [resolveDefaultDatabaseFile]: a test opens an explicit temp file and a
  /// headless daemon opens `NIGHTSHADE_DATABASE_DIR`, and `database_list`
  /// reports whichever one this connection actually holds.
  Future<Directory?> _databaseDirectory() async {
    final rows = await customSelect('PRAGMA database_list').get();
    for (final row in rows) {
      if (row.data['name'] != 'main') continue;
      // `file` is the empty string for an in-memory database and null on the
      // builds that omit the column — neither has a directory to put a marker
      // in, and both are answered by "no directory" rather than by a path
      // derived from nothing.
      final file = row.data['file'];
      if (file is! String || file.isEmpty) return null;
      return Directory(p.dirname(file));
    }
    return null;
  }

  /// Report a post-session integration that a previous process died in the
  /// middle of, then clear its marker.
  ///
  /// The pass leaves no `darkroom_jobs` row to recover — it enqueues the
  /// Darkroom job only after the masters exist — so the marker file written by
  /// `markIntegrationStarted` is the whole record that the night was
  /// interrupted. It is turned into two durable, operator-visible things:
  ///
  ///  - a line appended to the session's notes, which Session Review and the
  ///    session wire snapshot both carry, and
  ///  - a `warning` Night Narrator event on that session, which is what the
  ///    morning feed reads.
  ///
  /// The intended master files are named in both, EACH WITH WHAT IT ACTUALLY
  /// IS. A FITS truncated by a kill is present and non-empty and looks
  /// finished, so an operator told only "the integration was interrupted"
  /// would open one and trust it — and an operator told every present file is
  /// truncated would delete the ones that are whole. Each file is opened and
  /// measured against its own header before it is described.
  ///
  /// Re-running the integration is deliberately NOT automatic: the subs are
  /// still on disk and still graded, so nothing is lost by waiting, whereas a
  /// pass that re-launches itself at every open is how a crash-on-integrate
  /// takes the app down repeatedly. The report says the night needs a re-run;
  /// the operator asks for it.
  ///
  /// The marker is deleted last, so a process that dies between reading it and
  /// writing the report finds it again at the next open.
  Future<void> _reportInterruptedIntegration() async {
    final directory = await _databaseDirectory();
    if (directory == null) return;
    final interrupted = await readIntegrationMarker(directory);
    if (interrupted == null) return;

    // Each intended file is MEASURED before anything is said about it. The
    // pass writes its masters one after another, so an interruption leaves
    // some of them whole; calling every present file "truncated — delete it"
    // told the operator to throw away finished data, and the one that really
    // was half-written was buried in the same sentence as the ones that were
    // not.
    final present = await interrupted.presentMasterFiles();
    final incomplete = present.where((file) => !file.complete).toList();
    final whole = present.where((file) => file.complete).toList();
    final sentences = <String>[];
    if (present.isEmpty) {
      sentences.add(
        'No master file had been written yet, so nothing on disk is '
        'half-finished.',
      );
    }
    if (incomplete.isNotEmpty) {
      sentences.add(
        'These master files are incomplete — delete them before re-running: '
        '${incomplete.map((f) => '${f.path} (${f.detail})').join('; ')}.',
      );
    }
    for (final file in whole) {
      final registered = await _masterIsRegistered(file.path);
      sentences.add(
        registered
            ? '${file.path} is a complete FITS (${file.detail}) and the master '
                  'library already holds a row for it, so that one arrived '
                  'intact.'
            : '${file.path} is a complete FITS (${file.detail}) but no master '
                  'row records it, so it is finished on disk and missing from '
                  'the library. Re-running the integration writes it again; '
                  'nothing here says it is damaged.',
      );
    }
    final orphanText = sentences.join(' ');
    final startedAt = interrupted.startedAtUtc.toIso8601String();
    const headline =
        'The post-session integration was interrupted before it '
        'finished.';
    final body =
        'Nightshade closed while integrating this session (started '
        '$startedAt UTC). $orphanText The subs are all still on disk and '
        'still graded, so run the integration again when you are ready.';

    await customUpdate(
      'UPDATE imaging_sessions SET notes = '
      "CASE WHEN notes IS NULL OR notes = '' THEN ? "
      "ELSE notes || char(10) || ? END WHERE id = ?",
      variables: [
        Variable<String>('$headline $body'),
        Variable<String>('$headline $body'),
        Variable<int>(interrupted.sessionId),
      ],
      updates: {imagingSessions},
      updateKind: UpdateKind.update,
    );

    await customInsert(
      'INSERT INTO narrator_events('
      'session_id, timestamp, event_type, category, severity, headline, '
      'body, dedupe_key) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      variables: [
        Variable<int>(interrupted.sessionId),
        Variable<int>(DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000),
        const Variable<String>('quality.integration_interrupted'),
        const Variable<String>('quality'),
        const Variable<String>('warning'),
        const Variable<String>(headline),
        Variable<String>(body),
        // Session-scoped and stamped with the start instant, so re-reporting
        // the same interruption cannot duplicate the event while two separate
        // interrupted nights each keep their own.
        Variable<String>('quality.integration_interrupted:$startedAt'),
      ],
    );

    // ignore: avoid_print
    print(
      '[nightshade_db] Session ${interrupted.sessionId}: the post-session '
      'integration started at $startedAt UTC never finished. $orphanText',
    );

    await clearIntegrationMarker(directory);
  }

  /// Whether the master library already holds a row pointing at [path].
  ///
  /// The difference between "this file is finished" and "this file is finished
  /// AND the app knows about it": the integration writes the FITS and then
  /// records it, so a kill between the two leaves a whole master nothing
  /// references. That is a real thing to tell the operator, and it is not the
  /// same thing as a damaged file.
  Future<bool> _masterIsRegistered(String path) async {
    final rows = await customSelect(
      'SELECT 1 FROM integrated_masters WHERE master_fits_path = ? LIMIT 1',
      variables: [Variable<String>(path)],
    ).get();
    return rows.isNotEmpty;
  }

  Future<bool> _columnExists(String table, String column) async {
    final result = await customSelect("PRAGMA table_info('$table')").get();
    return result.any((row) => row.data['name'] == column);
  }

  Future<bool> _tableExists(String table) async {
    final result = await customSelect(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = '$table'",
    ).get();
    return result.isNotEmpty;
  }
}
