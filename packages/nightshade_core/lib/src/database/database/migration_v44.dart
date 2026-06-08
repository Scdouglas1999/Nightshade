part of '../database.dart';

extension _NightshadeDatabaseMigrationV44 on NightshadeDatabase {
  /// Version 44 (Phase C — finishing foundation): additive WCS + finishing
  /// artifact columns on the raw-DDL `integrated_masters` table, plus the new
  /// `narrowband_composites` table.
  ///
  /// The additive `integrated_masters` columns persist:
  ///   * the per-master **plate-solved WCS** as the eight FITS scalars in the
  ///     CD-matrix form ASTAP / `WcsInfo::from_plate_solve`
  ///     (`imaging/src/fits.rs:1094`) emit — reference world coordinates
  ///     (`wcs_crval1`, `wcs_crval2`), reference pixel (`wcs_crpix1`,
  ///     `wcs_crpix2`), and the CD matrix (`wcs_cd1_1`, `wcs_cd1_2`,
  ///     `wcs_cd2_1`, `wcs_cd2_2`). Persisting the master's own solved WCS is
  ///     what lights up the catalog-annotation overlay AND colour calibration
  ///     (both need a `WcsOverlay`). Storing the CD matrix (rather than
  ///     cdelt/crota) keeps the same sign convention as the native source of
  ///     truth; the `WcsOverlay` reader derives cdelt/crota from it.
  ///   * the **finishing output paths** for the gated post-steps whose artifacts
  ///     were previously written then discarded: `background_extracted_path`
  ///     (`<master>_bgx.fits`), `deconvolved_path` (`<master>_decon.fits`), and
  ///     `star_reduced_path` (`<master>_starred.fits`). The v42
  ///     `background_extracted` flag stays; this adds the actual artifact path so
  ///     the finished output can be surfaced.
  ///
  /// `narrowband_composites` is a new raw-DDL table — one row per applied
  /// SHO/HOO/etc. palette combine — carrying the palette, the component master
  /// ids it was built from, the output FITS path, and the composite dimensions.
  /// It is read/written via the plain [NarrowbandCompositesDao]
  /// (`customSelect`/`customInsert`), mirroring [NightReportsDao].
  ///
  /// Like v41/v42/v43 these are raw-DDL changes (the dominant v27+ convention)
  /// and do NOT require a Drift codegen pass.
  /// `_ensureIntegratedMastersV44Columns()` guards every
  /// `ALTER TABLE ... ADD COLUMN` with `_columnExists` and
  /// `_createNarrowbandCompositesTable()` uses `IF NOT EXISTS`, so both helpers
  /// are idempotent and also run from `onCreate` (fresh installs) so a fresh DB
  /// gets the columns and the table too.
  Future<void> _upgradeSchemaV44(Migrator m, int from) async {
    if (from < 44) {
      await _ensureIntegratedMastersV44Columns();
      await _createNarrowbandCompositesTable();
    }
  }
}
