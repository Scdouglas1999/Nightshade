import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/imaging/integrated_master.dart';
import '../../providers/database_provider.dart';
import '../database.dart';

/// Data-access object for the v41 `integrated_masters` + `integrated_master_frames`
/// tables — the persisted provenance for every archival integrated master the
/// post-session pipeline produces.
///
/// The tables are managed with raw DDL (see
/// [NightshadeDatabase._createPostSessionTables]) rather than drift `Table`
/// classes, so this DAO is a plain class that reads/writes through the
/// database's `customSelect`/`customStatement`/`customInsert` APIs — mirroring
/// [StackedResultsDao]. It is deliberately NOT a `@DriftAccessor`.
///
/// Per project policy this DAO never silently swallows failures: SQLite errors
/// propagate, the `(master_id, image_id)` UNIQUE constraint guards against
/// double-folding a sub, and reads map nullable columns to the model's
/// well-defined nullable fields rather than guessing.
class IntegratedMastersDao {
  IntegratedMastersDao(this._db);

  final NightshadeDatabase _db;

  static const String _columns = 'id, target_id, name, master_fits_path, '
      'preview_png_path, sidecar_path, rejection_map_path, status, '
      'accumulation_mode, channels, width, height, frame_count, '
      'total_integration_seconds, filter, settings_json, stats_json, '
      'created_at, updated_at';

  // ---------------------------------------------------------------------------
  // integrated_masters
  // ---------------------------------------------------------------------------

  /// Insert a new master row and return its id. [createdAt]/[updatedAt] default
  /// to "now" (UTC seconds) when omitted.
  Future<int> insertMaster({
    int? targetId,
    required String name,
    String? masterFitsPath,
    String? previewPngPath,
    String? sidecarPath,
    String? rejectionMapPath,
    required IntegratedMasterStatus status,
    required AccumulationMode accumulationMode,
    int channels = 1,
    int width = 0,
    int height = 0,
    int frameCount = 0,
    double totalIntegrationSeconds = 0.0,
    String? filter,
    String settingsJson = '{}',
    String statsJson = '{}',
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final now = DateTime.now().toUtc();
    return _db.customInsert(
      'INSERT INTO integrated_masters('
      'target_id, name, master_fits_path, preview_png_path, sidecar_path, '
      'rejection_map_path, status, accumulation_mode, channels, width, height, '
      'frame_count, total_integration_seconds, filter, settings_json, '
      'stats_json, created_at, updated_at'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      variables: [
        Variable<int>(targetId),
        Variable<String>(name),
        Variable<String>(masterFitsPath),
        Variable<String>(previewPngPath),
        Variable<String>(sidecarPath),
        Variable<String>(rejectionMapPath),
        Variable<String>(status.wire),
        Variable<String>(accumulationMode.wire),
        Variable<int>(channels),
        Variable<int>(width),
        Variable<int>(height),
        Variable<int>(frameCount),
        Variable<double>(totalIntegrationSeconds),
        Variable<String>(filter),
        Variable<String>(settingsJson),
        Variable<String>(statsJson),
        Variable<int>(_toEpochSeconds(createdAt ?? now)),
        Variable<int>(_toEpochSeconds(updatedAt ?? now)),
      ],
    );
  }

  /// Fetch a master by id, or null when absent.
  Future<IntegratedMaster?> getById(int id) async {
    final rows = await _db.customSelect(
      'SELECT $_columns FROM integrated_masters WHERE id = ? LIMIT 1',
      variables: [Variable<int>(id)],
    ).get();
    if (rows.isEmpty) return null;
    return _mapMaster(rows.first);
  }

  /// All masters, newest first.
  Future<List<IntegratedMaster>> getAll() async {
    final rows = await _db.customSelect(
      'SELECT $_columns FROM integrated_masters '
      'ORDER BY created_at DESC, id DESC',
    ).get();
    return rows.map(_mapMaster).toList();
  }

  /// Masters for a given target, newest first.
  Future<List<IntegratedMaster>> getForTarget(int targetId) async {
    final rows = await _db.customSelect(
      'SELECT $_columns FROM integrated_masters '
      'WHERE target_id = ? ORDER BY created_at DESC, id DESC',
      variables: [Variable<int>(targetId)],
    ).get();
    return rows.map(_mapMaster).toList();
  }

  /// The active accumulating master for a (target, filter) pair, or null. Used
  /// by the auto-process hook to decide whether to fold tonight's subs into an
  /// existing master vs. start a one-shot integration.
  Future<IntegratedMaster?> getAccumulatingForTargetFilter({
    required int targetId,
    String? filter,
  }) async {
    final hasFilter = filter != null && filter.trim().isNotEmpty;
    final rows = await _db.customSelect(
      'SELECT $_columns FROM integrated_masters '
      'WHERE target_id = ? AND status = ? '
      '${hasFilter ? 'AND filter = ?' : 'AND (filter IS NULL OR filter = \'\')'} '
      'ORDER BY created_at DESC, id DESC LIMIT 1',
      variables: [
        Variable<int>(targetId),
        Variable<String>(IntegratedMasterStatus.accumulating.wire),
        if (hasFilter) Variable<String>(filter.trim()),
      ],
    ).get();
    if (rows.isEmpty) return null;
    return _mapMaster(rows.first);
  }

  /// Apply a bookkeeping update after an accumulation `add`/`finalize`. Only the
  /// supplied fields are written; `updated_at` is always bumped to now.
  Future<int> updateBookkeeping(
    int id, {
    String? masterFitsPath,
    String? previewPngPath,
    String? rejectionMapPath,
    IntegratedMasterStatus? status,
    int? channels,
    int? width,
    int? height,
    int? frameCount,
    double? totalIntegrationSeconds,
    String? statsJson,
  }) {
    final sets = <String>['updated_at = ?'];
    final vars = <Variable<Object>>[
      Variable<int>(_toEpochSeconds(DateTime.now().toUtc())),
    ];
    void put(String col, Variable<Object> v) {
      sets.add('$col = ?');
      vars.add(v);
    }

    if (masterFitsPath != null) {
      put('master_fits_path', Variable<String>(masterFitsPath));
    }
    if (previewPngPath != null) {
      put('preview_png_path', Variable<String>(previewPngPath));
    }
    if (rejectionMapPath != null) {
      put('rejection_map_path', Variable<String>(rejectionMapPath));
    }
    if (status != null) put('status', Variable<String>(status.wire));
    if (channels != null) put('channels', Variable<int>(channels));
    if (width != null) put('width', Variable<int>(width));
    if (height != null) put('height', Variable<int>(height));
    if (frameCount != null) put('frame_count', Variable<int>(frameCount));
    if (totalIntegrationSeconds != null) {
      put('total_integration_seconds',
          Variable<double>(totalIntegrationSeconds));
    }
    if (statsJson != null) put('stats_json', Variable<String>(statsJson));

    vars.add(Variable<int>(id));
    return _db.customUpdate(
      'UPDATE integrated_masters SET ${sets.join(', ')} WHERE id = ?',
      variables: vars,
      updateKind: UpdateKind.update,
    );
  }

  /// Apply the v42 Smart-Morning-Report fields to a master. Only the supplied
  /// fields are written; `updated_at` is always bumped to now. Mirrors
  /// [updateBookkeeping] but targets the additive v42 columns
  /// (`_ensureIntegratedMastersV42Columns`):
  ///
  ///  * [colorCalibratedPath] / [annotatedPreviewPath] — catalog-powered
  ///    finishing artifacts.
  ///  * [backgroundExtracted] — whether background extraction has been applied.
  ///  * [targetSnr] / [targetIntegrationS] — the per-master SNR/time goals the
  ///    "how much more?" loop reads.
  ///  * [improvementCurveJson] — a serialized [IntegrationCurve]
  ///    (`IntegrationCurve.toJson` → `jsonEncode`); pass the encoded string.
  Future<int> updateSmartFields(
    int id, {
    String? colorCalibratedPath,
    String? annotatedPreviewPath,
    bool? backgroundExtracted,
    double? targetSnr,
    double? targetIntegrationS,
    String? improvementCurveJson,
  }) {
    final sets = <String>['updated_at = ?'];
    final vars = <Variable<Object>>[
      Variable<int>(_toEpochSeconds(DateTime.now().toUtc())),
    ];
    void put(String col, Variable<Object> v) {
      sets.add('$col = ?');
      vars.add(v);
    }

    if (colorCalibratedPath != null) {
      put('color_calibrated_path', Variable<String>(colorCalibratedPath));
    }
    if (annotatedPreviewPath != null) {
      put('annotated_preview_path', Variable<String>(annotatedPreviewPath));
    }
    if (backgroundExtracted != null) {
      put('background_extracted', Variable<int>(backgroundExtracted ? 1 : 0));
    }
    if (targetSnr != null) put('target_snr', Variable<double>(targetSnr));
    if (targetIntegrationS != null) {
      put('target_integration_s', Variable<double>(targetIntegrationS));
    }
    if (improvementCurveJson != null) {
      put('improvement_curve_json', Variable<String>(improvementCurveJson));
    }

    vars.add(Variable<int>(id));
    return _db.customUpdate(
      'UPDATE integrated_masters SET ${sets.join(', ')} WHERE id = ?',
      variables: vars,
      updateKind: UpdateKind.update,
    );
  }

  /// Delete a master (cascades to its `integrated_master_frames` rows via the FK).
  Future<int> deleteMaster(int id) {
    return _db.customUpdate(
      'DELETE FROM integrated_masters WHERE id = ?',
      variables: [Variable<int>(id)],
      updateKind: UpdateKind.delete,
    );
  }

  // ---------------------------------------------------------------------------
  // integrated_master_frames (join / dedup)
  // ---------------------------------------------------------------------------

  /// Record that [imageId] was folded into [masterId]. Idempotent: the
  /// `(master_id, image_id)` UNIQUE constraint means a re-fold is an
  /// `INSERT OR REPLACE` that refreshes the weight/residual rather than
  /// duplicating the row. Returns the affected row id.
  ///
  /// [snr] / [fwhm] / [eccentricity] are the v42 per-sub science metrics the
  /// Night Doctor reads after a morning integration (`integrated_master_frames`
  /// additive columns). All three are nullable and default to null so existing
  /// callers stay source-compatible.
  Future<int> recordFoldedFrame({
    required int masterId,
    required int imageId,
    double? weight,
    double? alignmentResidualPx,
    bool accepted = true,
    String? rejectionReason,
    DateTime? foldedAt,
    double? snr,
    double? fwhm,
    double? eccentricity,
  }) {
    return _db.customInsert(
      'INSERT OR REPLACE INTO integrated_master_frames('
      'master_id, image_id, weight, alignment_residual_px, accepted, '
      'rejection_reason, folded_at, snr, fwhm, eccentricity'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      variables: [
        Variable<int>(masterId),
        Variable<int>(imageId),
        Variable<double>(weight),
        Variable<double>(alignmentResidualPx),
        Variable<int>(accepted ? 1 : 0),
        Variable<String>(rejectionReason),
        Variable<int>(
            _toEpochSeconds((foldedAt ?? DateTime.now()).toUtc())),
        Variable<double>(snr),
        Variable<double>(fwhm),
        Variable<double>(eccentricity),
      ],
    );
  }

  /// The set of `captured_images.id` already folded into [masterId]. The dedup
  /// source of truth: [MasterAccumulationService] subtracts this from the
  /// freshly-selected subs before an `add`.
  Future<Set<int>> getFoldedImageIds(int masterId) async {
    final rows = await _db.customSelect(
      'SELECT image_id FROM integrated_master_frames WHERE master_id = ?',
      variables: [Variable<int>(masterId)],
    ).get();
    return rows.map((r) => r.read<int>('image_id')).toSet();
  }

  /// All fold records for a master, newest first.
  Future<List<IntegratedMasterFrame>> getFramesForMaster(int masterId) async {
    final rows = await _db.customSelect(
      'SELECT id, master_id, image_id, weight, alignment_residual_px, '
      'accepted, rejection_reason, folded_at '
      'FROM integrated_master_frames WHERE master_id = ? '
      'ORDER BY folded_at DESC, id DESC',
      variables: [Variable<int>(masterId)],
    ).get();
    return rows.map((r) {
      return IntegratedMasterFrame(
        id: r.read<int>('id'),
        masterId: r.read<int>('master_id'),
        imageId: r.read<int>('image_id'),
        weight: r.readNullable<double>('weight'),
        alignmentResidualPx: r.readNullable<double>('alignment_residual_px'),
        accepted: r.read<int>('accepted') != 0,
        rejectionReason: r.readNullable<String>('rejection_reason'),
        foldedAt: _fromEpochSeconds(r.read<int>('folded_at')),
      );
    }).toList();
  }

  IntegratedMaster _mapMaster(QueryRow row) {
    return IntegratedMaster(
      id: row.read<int>('id'),
      targetId: row.readNullable<int>('target_id'),
      name: row.read<String>('name'),
      masterFitsPath: row.readNullable<String>('master_fits_path'),
      previewPngPath: row.readNullable<String>('preview_png_path'),
      sidecarPath: row.readNullable<String>('sidecar_path'),
      rejectionMapPath: row.readNullable<String>('rejection_map_path'),
      status: IntegratedMasterStatus.fromWire(row.read<String>('status')),
      accumulationMode:
          AccumulationMode.fromWire(row.read<String>('accumulation_mode')),
      channels: row.read<int>('channels'),
      width: row.read<int>('width'),
      height: row.read<int>('height'),
      frameCount: row.read<int>('frame_count'),
      totalIntegrationSeconds: row.read<double>('total_integration_seconds'),
      filter: row.readNullable<String>('filter'),
      settingsJson: row.read<String>('settings_json'),
      statsJson: row.read<String>('stats_json'),
      createdAt: _fromEpochSeconds(row.read<int>('created_at')),
      updatedAt: _fromEpochSeconds(row.read<int>('updated_at')),
    );
  }

  static int _toEpochSeconds(DateTime when) =>
      when.toUtc().millisecondsSinceEpoch ~/ 1000;

  static DateTime _fromEpochSeconds(int seconds) =>
      DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
}

/// Riverpod provider for [IntegratedMastersDao].
final integratedMastersDaoProvider = Provider<IntegratedMastersDao>((ref) {
  return IntegratedMastersDao(ref.watch(databaseProvider));
});
