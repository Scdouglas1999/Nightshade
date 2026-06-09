part of '../database.dart';

extension _NightshadeDatabaseMigrationV45 on NightshadeDatabase {
  /// Version 45 (Mosaic M2 — durable mosaic projects): the `mosaic_projects` +
  /// `mosaic_panels` tables, making a mosaic a first-class durable entity that
  /// links the grid configuration → per-panel capture targets → per-panel
  /// integrated masters → the final stitched mosaic master.
  ///
  /// `mosaic_projects` persists one row per mosaic (target region + grid: rows ×
  /// cols, overlap %, position angle), its lifecycle `status`
  /// (`planning|capturing|integrating|stitching|complete`), and the stitched
  /// output's `integrated_masters.id` (`output_master_id`). `mosaic_panels`
  /// persists one row per panel (`UNIQUE(project_id, panel_index)`) carrying the
  /// panel center RA/Dec, the per-panel capture `target_id` (which reuses the
  /// existing `(target, filter)` campaign + integration-goal machinery for
  /// per-panel goals across nights), the per-panel `integrated_master_id`
  /// (whose v44 WCS columns carry the panel's plate-solved geometry), a running
  /// `captured_count`, and the panel `status`.
  ///
  /// Both are read/written via the plain [MosaicProjectsDao] / [MosaicPanelsDao]
  /// (`customSelect`/`customInsert`), mirroring [CampaignsDao] /
  /// [NarrowbandCompositesDao].
  ///
  /// Like v41/v42/v43/v44 these are raw-DDL changes (the dominant v27+
  /// convention) and do NOT require a Drift codegen pass.
  /// `_createMosaicTables()` uses `CREATE TABLE/INDEX IF NOT EXISTS`, so the
  /// helper is idempotent and also runs from `onCreate` (fresh installs) so a
  /// fresh DB gets the tables too.
  Future<void> _upgradeSchemaV45(Migrator m, int from) async {
    if (from < 45) {
      await _createMosaicTables();
    }
  }
}
